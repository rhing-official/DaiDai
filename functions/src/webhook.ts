import { createHash, randomBytes, timingSafeEqual } from "crypto";

/**
 * 受信Webhook（寄合へ外部から投稿できる、bot・API段階1、2026-10-10追加）の
 * 純粋なロジック。Firestore・HTTPには依存させず、単体テスト
 * （`webhook.test.ts`）できる形にしてある。
 */

/** 1つの広場に作れるWebhookの最大数。 */
export const WEBHOOK_MAX_PER_GROUP = 10;

/** Webhookの名前（BOT名として表示される）の最大文字数。 */
export const WEBHOOK_NAME_MAX_LENGTH = 40;

/** 投稿本文の最大文字数。 */
export const WEBHOOK_CONTENT_MAX_LENGTH = 2000;

/** リクエストボディの最大サイズ（バイト）。 */
export const WEBHOOK_BODY_MAX_BYTES = 10 * 1024;

/** 1つのWebhookあたりのレート制限（`WEBHOOK_RATE_WINDOW_MS`あたりの件数）。 */
export const WEBHOOK_RATE_LIMIT = 30;
export const WEBHOOK_RATE_WINDOW_MS = 60 * 1000;

/** Webhook由来のメッセージの`senderId`（`users`ドキュメントは存在しない）。 */
export function webhookSenderId(webhookId: string): string {
  return `webhook:${webhookId}`;
}

/** URLに入れる秘密のトークン（32バイトの乱数、base64url）。 */
export function generateWebhookToken(): string {
  return randomBytes(32).toString("base64url");
}

/** 保存用のトークンのハッシュ（平文は保存しない）。 */
export function hashWebhookToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** [token]のハッシュが保存済みの[storedHash]と一致するか（定数時間比較）。 */
export function verifyWebhookToken(token: string, storedHash: unknown): boolean {
  if (typeof storedHash !== "string" || storedHash.length !== 64) return false;
  const actual = Buffer.from(hashWebhookToken(token), "hex");
  const expected = Buffer.from(storedHash, "hex");
  if (actual.length !== expected.length) return false;
  return timingSafeEqual(actual, expected);
}

/** Webhookの名前を検証して整える。不正ならnull。 */
export function normalizeWebhookName(name: unknown): string | null {
  if (typeof name !== "string") return null;
  const trimmed = name.trim();
  if (trimmed.length === 0 || trimmed.length > WEBHOOK_NAME_MAX_LENGTH) {
    return null;
  }
  return trimmed;
}

export interface ParsedWebhookPath {
  groupId: string;
  webhookId: string;
  token: string;
}

/**
 * リクエストパスから`{groupId}/{webhookId}/{token}`を取り出す。関数名の
 * セグメント（`postWebhookMessage`）が先頭に付く場合も許容する。
 */
export function parseWebhookPath(path: string): ParsedWebhookPath | null {
  const segments = path.split("/").filter((s) => s.length > 0);
  if (segments[0] === "postWebhookMessage") segments.shift();
  if (segments.length !== 3) return null;
  const [groupId, webhookId, token] = segments;
  const valid = /^[A-Za-z0-9_-]{1,128}$/;
  if (!valid.test(groupId) || !valid.test(webhookId) || !valid.test(token)) {
    return null;
  }
  return { groupId, webhookId, token };
}

export type PayloadResult =
  | { ok: true; content: string; silent: boolean }
  | { ok: false; reason: string };

/** 投稿のJSONボディを検証する（`{ "content": string, "silent"?: boolean }`）。 */
export function parseWebhookPayload(body: unknown): PayloadResult {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, reason: "JSONオブジェクトで送ってください" };
  }
  const { content, silent } = body as Record<string, unknown>;
  if (typeof content !== "string") {
    return { ok: false, reason: "contentは文字列で指定してください" };
  }
  if (content.trim().length === 0) {
    return { ok: false, reason: "contentが空です" };
  }
  if (content.length > WEBHOOK_CONTENT_MAX_LENGTH) {
    return {
      ok: false,
      reason: `contentは${WEBHOOK_CONTENT_MAX_LENGTH}文字以内にしてください`,
    };
  }
  if (silent !== undefined && typeof silent !== "boolean") {
    return { ok: false, reason: "silentは真偽値で指定してください" };
  }
  return { ok: true, content, silent: silent === true };
}

export interface RateState {
  windowStartMs: number | null;
  count: number;
}

export interface RateDecision extends RateState {
  allowed: boolean;
}

/**
 * 固定窓のレート制限。窓が切れていれば新しい窓を開始して1件目として許可し、
 * 窓内で上限に達していれば拒否する（拒否した分は数えない）。
 */
export function nextRateState(prev: RateState, nowMs: number): RateDecision {
  const expired =
    prev.windowStartMs === null ||
    nowMs - prev.windowStartMs >= WEBHOOK_RATE_WINDOW_MS;
  if (expired) {
    return { allowed: true, windowStartMs: nowMs, count: 1 };
  }
  if (prev.count >= WEBHOOK_RATE_LIMIT) {
    return { allowed: false, windowStartMs: prev.windowStartMs, count: prev.count };
  }
  return {
    allowed: true,
    windowStartMs: prev.windowStartMs,
    count: prev.count + 1,
  };
}

/**
 * 広場[group]で[uid]がbot・Webhookを管理できるか。長は常に可、それ以外は
 * `memberPermissions`に`manageBots`を持つ人のみ（firestore.rulesの
 * `hasGroupPermission`と同じ判定）。
 */
export function canManageBots(
  group: FirebaseFirestore.DocumentData | undefined,
  uid: string,
): boolean {
  if (!group) return false;
  if (group.ownerId === uid) return true;
  const permissions = group.memberPermissions?.[uid];
  return Array.isArray(permissions) && permissions.includes("manageBots");
}
