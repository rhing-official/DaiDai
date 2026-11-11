/**
 * 複数アカウントの切り替え（2026-11-11）の判定。端末に保存した「切り替え用の合言葉」を
 * サーバーが検証し、カスタムトークンを発行する。ここは副作用の無い純関数（Firebase非依存）
 * で、`index.ts`のcallableから使い、単体テストする。設計は`文書/複数アカウント.md`。
 *
 * 「保存済みのうち1つでも極みなら切り替えできる」は、端末の件数を信用せずに強制するため、
 * 各セッションに`kiwamiOwnerUid`（そのセッションを許可した極みのアカウント）を持たせる。
 * - 極みのアカウントが自分用に作る: 自分自身。
 * - 極みでないアカウントを足す: 極みのアカウントが発行した追加チケットで作る（所有者はその極み）。
 * - 切り替えが通る条件: 所有者が今も極み、又は切り替え先自身が極み。極みが切れれば止まる。
 */
import { createHash, randomBytes, timingSafeEqual } from "crypto";

/** セッションの有効期間（使うたびに延びる）。 */
export const SWITCH_SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;
/** 追加チケットの有効期間。 */
export const SWITCH_TICKET_TTL_MS = 10 * 60 * 1000;
/** 合言葉の連続失敗でセッションを失効させる回数。 */
export const SWITCH_MAX_FAILURES = 5;
/** 1人のアカウントが同時に持てるセッション数（端末3台分の余裕込みの上限）。 */
export const SWITCH_MAX_SESSIONS_PER_USER = 10;

export type Check =
  | { ok: true }
  | { ok: false; code: string; message: string };

/** 推測できない値（合言葉・追加チケット）を作る。 */
export function generateSecret(): string {
  return randomBytes(32).toString("base64url");
}

/** 合言葉・チケットのハッシュ。十分に長いランダム値なので、遅いハッシュは要らない。 */
export function hashSecret(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

/** [secret]のハッシュが[hash]と一致するか（定数時間）。 */
export function verifySecret(secret: string, hash: unknown): boolean {
  if (typeof secret !== "string" || typeof hash !== "string") return false;
  const a = Buffer.from(hashSecret(secret), "hex");
  const b = Buffer.from(hash, "hex");
  if (a.length === 0 || a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** ユーザー文書から、極みの契約状態を読む（`subscriptionPlan`が`kiwami`）。 */
export function isKiwamiPlan(userData: { subscriptionPlan?: unknown } | undefined): boolean {
  return userData?.subscriptionPlan === "kiwami";
}

/** アカウントが切り替え先として使える状態か（欠落は`active`扱い）。 */
export function isActiveAccount(userData: { accountStatus?: unknown } | undefined): boolean {
  if (!userData) return false;
  const status = userData.accountStatus;
  return status === undefined || status === "active";
}

export interface AddTicket {
  ownerUid?: unknown;
  expiresAtMs?: unknown;
}

/**
 * セッションを作れるか、作れるなら所有者（`kiwamiOwnerUid`）は誰か。
 * [callerIsKiwami]: 呼んだ本人が極みか。[ticket]: 追加チケットの文書（無ければ`undefined`）。
 * [ticketOwnerIsKiwami]: チケット発行者が今も極みか。
 */
export function decideSessionOwner(params: {
  callerUid: string;
  callerIsKiwami: boolean;
  ticket?: AddTicket;
  ticketOwnerIsKiwami?: boolean;
  nowMs: number;
}): { ok: true; kiwamiOwnerUid: string } | { ok: false; code: string; message: string } {
  if (params.callerIsKiwami) {
    return { ok: true, kiwamiOwnerUid: params.callerUid };
  }
  const ticket = params.ticket;
  if (!ticket) {
    return {
      ok: false,
      code: "failed-precondition",
      message: "アカウントを追加するには、極みのアカウントからの追加が必要です",
    };
  }
  const expiresAtMs = ticket.expiresAtMs;
  if (typeof expiresAtMs !== "number" || expiresAtMs < params.nowMs) {
    return {
      ok: false,
      code: "deadline-exceeded",
      message: "追加の有効期限が切れています。もう一度、極みのアカウントから追加してください",
    };
  }
  const ownerUid = ticket.ownerUid;
  if (typeof ownerUid !== "string" || ownerUid === params.callerUid) {
    return { ok: false, code: "permission-denied", message: "この追加は使えません" };
  }
  if (!params.ticketOwnerIsKiwami) {
    return {
      ok: false,
      code: "failed-precondition",
      message: "追加元のアカウントが極みではありません",
    };
  }
  return { ok: true, kiwamiOwnerUid: ownerUid };
}

export interface SwitchSessionData {
  secretHash?: unknown;
  kiwamiOwnerUid?: unknown;
  expiresAtMs?: unknown;
  failures?: unknown;
  revoked?: unknown;
}

/** 切り替え（合言葉の検証）の結果。`badSecret`は呼び出し側が失敗回数を増やす。 */
export type RedeemOutcome =
  | { kind: "ok" }
  | { kind: "badSecret"; revoke: boolean }
  | { kind: "deny"; code: string; message: string };

const GENERIC_DENY = {
  kind: "deny" as const,
  code: "permission-denied",
  message: "切り替えできません。もう一度ログインしてください",
};

/**
 * 切り替えの可否。順序は、①存在・失効・期限・失敗回数 ②合言葉 ③アカウントの状態
 * ④極みの条件。①②は、存在や理由を外から推測されないよう同じ文言で拒否する。
 */
export function evaluateRedeem(params: {
  session: SwitchSessionData | undefined;
  secret: unknown;
  nowMs: number;
  targetUser: { accountStatus?: unknown; subscriptionPlan?: unknown } | undefined;
  ownerUser: { subscriptionPlan?: unknown } | undefined;
}): RedeemOutcome {
  const { session, secret, nowMs, targetUser, ownerUser } = params;
  if (!session || session.revoked === true) return GENERIC_DENY;
  const expiresAtMs = session.expiresAtMs;
  if (typeof expiresAtMs !== "number" || expiresAtMs < nowMs) return GENERIC_DENY;
  const failures = typeof session.failures === "number" ? session.failures : 0;
  if (failures >= SWITCH_MAX_FAILURES) return GENERIC_DENY;

  if (typeof secret !== "string" || !verifySecret(secret, session.secretHash)) {
    return { kind: "badSecret", revoke: failures + 1 >= SWITCH_MAX_FAILURES };
  }

  if (!isActiveAccount(targetUser)) {
    return {
      kind: "deny",
      code: "failed-precondition",
      message: "このアカウントは現在使えません",
    };
  }
  if (!isKiwamiPlan(ownerUser) && !isKiwamiPlan(targetUser)) {
    return {
      kind: "deny",
      code: "failed-precondition",
      message: "極みの契約が切れているため、アカウントを切り替えられません",
    };
  }
  return { kind: "ok" };
}
