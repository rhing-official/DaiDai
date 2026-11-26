/**
 * 素材パックの審査結果（承認・差し戻し・配信停止）の本体（2026-11-26）。Firebase の SDK に依存しない。
 * トリガー側（`index.ts`）は、`ReviewStore` の実装と、`ReviewError` から `HttpsError` への変換、
 * 管理者の確認、監査ログだけを持つ。自前化の時に、この本体だけを別サーバーへ移せるようにする。
 * 取得・取り下げ・アンインストールは、`themePackOwnership.ts`。
 */
import { parseThemePack, validateThemePackFiles, type ThemePackBrightness } from "./themePack";

export type ReviewErrorCode = "invalid-argument" | "not-found" | "failed-precondition";

/** 管理者へそのまま見せてよい日本語の理由を持つ */
export class ReviewError extends Error {
  constructor(
    readonly code: ReviewErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export const NOTICE_KINDS = {
  approved: "themePackApproved",
  rejected: "themePackRejected",
  suspended: "themePackSuspended",
} as const;

export const MAX_REASON_LENGTH = 500;
/** 取得した人へのお知らせを、1回に書く件数（Firestore の 500 件の上限より小さく） */
export const NOTICE_CHUNK_SIZE = 400;

/** 審査できる投稿の状態 */
const REVIEWABLE = ["submitted", "inReview"] as const;

export interface ReviewSubmission {
  creatorId: string;
  packId: string;
  version: number;
  status: string;
  assetPath: string;
  /** 補強前の古い文書には無い */
  name?: string;
  brightness?: string;
}

export interface PublicPack {
  creatorId: string;
  name: string;
  version: number;
  status: string;
}

export interface Notice {
  kind: string;
  packId: string;
  content: string;
  /** 指定すると、同じ文書を上書きする（再実行で重ならない）。無ければ新しい文書 */
  id?: string;
}

export interface StoredFile {
  name: string;
  size: number;
  contentType: string | undefined;
}

/** 1回の transaction の中で使う窓口 */
export interface ReviewTx {
  getSubmission(submissionId: string): Promise<ReviewSubmission | null>;
  getPublicPack(packId: string): Promise<PublicPack | null>;
  /** 同じ `packId` と `version` の投稿。1件のはず */
  findSubmission(packId: string, version: number): Promise<{ id: string; status: string } | null>;
  updateSubmission(submissionId: string, patch: Record<string, unknown>): void;
  /** 初回の公開。`createdAt`・`ownerCount: 0`・`price: 0` も、ここで入れる */
  createPublicPack(packId: string, data: PublicPackData): void;
  /** 新しい版の公開。`createdAt`・`ownerCount`・`price` には触れない */
  updatePublicPack(packId: string, data: PublicPackData): void;
  suspendPublicPack(packId: string): void;
  addNotice(uid: string, notice: Notice): void;
}

export interface PublicPackData {
  name: string;
  creatorId: string;
  brightness: ThemePackBrightness;
  version: number;
  /** `themePacks/{packId}/{version}`。URL は持たない */
  assetPath: string;
}

export interface ReviewStore {
  listFiles(prefix: string): Promise<StoredFile[]>;
  readFile(prefix: string, name: string): Promise<Uint8Array>;
  copyFile(fromPrefix: string, toPrefix: string, name: string): Promise<void>;
  runTransaction<T>(fn: (tx: ReviewTx) => Promise<T>): Promise<T>;
  /** `ownedThemePacks` を `packId` で引いた持ち主の一覧 */
  listOwnerUids(packId: string): Promise<string[]>;
  /** `uids` 全員へ同じお知らせを、1回のまとまりで書く */
  writeNoticeBatch(uids: string[], notice: Notice): Promise<void>;
}

// ---------------------------------------------------------------------------
// お知らせの文面
// ---------------------------------------------------------------------------

export function approvedNoticeText(name: string): string {
  return `意匠パック『${name}』が承認され、公開されました。`;
}
export function rejectedNoticeText(name: string, reason: string): string {
  return `意匠パック『${name}』は、差し戻されました。理由は次のとおりです。\n${reason}`;
}
export function suspendedCreatorNoticeText(name: string, reason: string): string {
  return `意匠パック『${name}』の配信を停止しました。理由は次のとおりです。\n${reason}`;
}
export function suspendedOwnerNoticeText(name: string): string {
  return `取得した意匠パック『${name}』の配信が停止されました。表示は標準に戻ります。`;
}

export function publicAssetPath(packId: string, version: number): string {
  return `themePacks/${packId}/${version}`;
}

/** 取得した人へのお知らせの文書 ID。再実行しても、同じ文書を上書きするだけにする */
export function ownerSuspendNoticeId(packId: string): string {
  return `themePackSuspended-${packId}`;
}

// ---------------------------------------------------------------------------
// 入力
// ---------------------------------------------------------------------------

function readString(data: unknown, key: string): string {
  const v = (data as Record<string, unknown> | null | undefined)?.[key];
  if (typeof v !== "string" || !v) {
    throw new ReviewError("invalid-argument", `${key}が必要です。`);
  }
  return v;
}

function readReason(data: unknown): string {
  const v = (data as { reason?: unknown } | null | undefined)?.reason;
  const reason = typeof v === "string" ? v.trim() : "";
  if (!reason) throw new ReviewError("invalid-argument", "理由を入力してください。");
  if ([...reason].length > MAX_REASON_LENGTH) {
    throw new ReviewError("invalid-argument", `理由は${MAX_REASON_LENGTH}文字以内にしてください。`);
  }
  return reason;
}

/** 古い投稿には `name` が無い。Storage の pack.json から補う */
async function resolveName(store: ReviewStore, sub: ReviewSubmission): Promise<string> {
  if (sub.name) return sub.name;
  try {
    const bytes = await store.readFile(sub.assetPath, "pack.json");
    const parsed = parseThemePack(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (parsed.ok) return parsed.pack.name;
  } catch {
    // 読めなくても、審査の結果は出せるようにする
  }
  return "名称未設定";
}

// ---------------------------------------------------------------------------
// 承認
// ---------------------------------------------------------------------------

export interface ApproveResult {
  submissionId: string;
  packId: string;
  creatorId: string;
  version: number;
  status: "approved";
  /** 今回の呼び出しで、状態を変えた（二重の呼び出しでは false） */
  changed: boolean;
}

function assertApprovable(sub: ReviewSubmission, pub: PublicPack | null): void {
  if (!(REVIEWABLE as readonly string[]).includes(sub.status)) {
    throw new ReviewError("failed-precondition", "この投稿は、承認できる状態ではありません。");
  }
  if (pub?.status === "suspended") {
    throw new ReviewError("failed-precondition", "このパックは配信を停止しています。新しい版は承認できません。");
  }
  if (pub && sub.version <= pub.version) {
    throw new ReviewError("failed-precondition", "公開中の版より新しくないため、承認できません。差し戻してください。");
  }
}

export interface ApproveInput {
  adminUid: string;
  data: unknown;
}

export async function approveThemePack(store: ReviewStore, input: ApproveInput): Promise<ApproveResult> {
  const submissionId = readString(input.data, "submissionId");

  // 下見: 状態を確かめてから、素材を読む（承認できない投稿の素材を、公開側へ置かない）
  const pre = await store.runTransaction(async (tx) => {
    const sub = await tx.getSubmission(submissionId);
    if (!sub) throw new ReviewError("not-found", "投稿が見つかりません。");
    if (sub.status === "approved") return { sub, done: true };
    assertApprovable(sub, await tx.getPublicPack(sub.packId));
    return { sub, done: false };
  });
  if (pre.done) return resultOf(submissionId, pre.sub, false);
  const sub = pre.sub;

  // 素材を読み直して、再検査する（提出の後に変わっていないか、検査の規則が変わっていないか）
  const listed = await store.listFiles(sub.assetPath);
  const files = new Map<string, Uint8Array>();
  for (const f of listed) files.set(f.name, await store.readFile(sub.assetPath, f.name));
  const checked = validateThemePackFiles(files);
  if (!checked.ok) {
    throw new ReviewError("failed-precondition", `意匠パックの再検査に通りません。${checked.errors.join("")}`);
  }
  if (`${sub.creatorId}__${checked.pack.id}` !== sub.packId) {
    throw new ReviewError("failed-precondition", "素材のidが、投稿の記録と一致しません。");
  }

  // 公開用の場所へコピーする。同じ場所への再実行は、上書きになる。投稿の場所は、そのまま残す
  const toPrefix = publicAssetPath(sub.packId, sub.version);
  for (const name of files.keys()) await store.copyFile(sub.assetPath, toPrefix, name);

  const name = checked.pack.name;
  return store.runTransaction(async (tx) => {
    // 並行した呼び出しへの備えとして、transaction の中でも確かめる
    const again = await tx.getSubmission(submissionId);
    if (!again) throw new ReviewError("not-found", "投稿が見つかりません。");
    if (again.status === "approved") return resultOf(submissionId, again, false);
    const pub = await tx.getPublicPack(again.packId);
    assertApprovable(again, pub);

    const data: PublicPackData = {
      name,
      creatorId: again.creatorId,
      brightness: checked.pack.brightness,
      version: again.version,
      assetPath: toPrefix,
    };
    if (pub) tx.updatePublicPack(again.packId, data);
    else tx.createPublicPack(again.packId, data);
    tx.updateSubmission(submissionId, {
      status: "approved",
      decidedBy: input.adminUid,
      name,
      brightness: checked.pack.brightness,
    });
    tx.addNotice(again.creatorId, {
      kind: NOTICE_KINDS.approved,
      packId: again.packId,
      content: approvedNoticeText(name),
    });
    return resultOf(submissionId, again, true);
  });
}

function resultOf(submissionId: string, sub: ReviewSubmission, changed: boolean): ApproveResult {
  return { submissionId, packId: sub.packId, creatorId: sub.creatorId, version: sub.version, status: "approved", changed };
}

// ---------------------------------------------------------------------------
// 差し戻し
// ---------------------------------------------------------------------------

export interface RejectResult {
  submissionId: string;
  packId: string;
  creatorId: string;
  status: "rejected";
}

export async function rejectThemePack(store: ReviewStore, input: ApproveInput): Promise<RejectResult> {
  const submissionId = readString(input.data, "submissionId");
  const reason = readReason(input.data);

  const pre = await store.runTransaction((tx) => tx.getSubmission(submissionId));
  if (!pre) throw new ReviewError("not-found", "投稿が見つかりません。");
  const name = await resolveName(store, pre);

  return store.runTransaction(async (tx) => {
    const sub = await tx.getSubmission(submissionId);
    if (!sub) throw new ReviewError("not-found", "投稿が見つかりません。");
    if (!(REVIEWABLE as readonly string[]).includes(sub.status)) {
      throw new ReviewError("failed-precondition", "この投稿は、差し戻せる状態ではありません。");
    }
    tx.updateSubmission(submissionId, {
      status: "rejected",
      decisionNote: reason,
      decidedBy: input.adminUid,
    });
    tx.addNotice(sub.creatorId, {
      kind: NOTICE_KINDS.rejected,
      packId: sub.packId,
      content: rejectedNoticeText(name, reason),
    });
    return { submissionId, packId: sub.packId, creatorId: sub.creatorId, status: "rejected" as const };
  });
}

// ---------------------------------------------------------------------------
// 配信停止
// ---------------------------------------------------------------------------

export interface SuspendResult {
  packId: string;
  creatorId: string;
  status: "suspended";
  /** 取得した人へ書いたお知らせの数 */
  notifiedOwners: number;
  /** 今回の呼び出しで、状態を変えた（停止済みの再実行では false） */
  changed: boolean;
}

export async function suspendThemePack(store: ReviewStore, input: ApproveInput): Promise<SuspendResult> {
  const packId = readString(input.data, "packId");
  const reason = readReason(input.data);

  const outcome = await store.runTransaction(async (tx) => {
    const pub = await tx.getPublicPack(packId);
    if (!pub) throw new ReviewError("not-found", "公開中のパックが見つかりません。");
    if (pub.status === "suspended") return { pub, changed: false };
    // 取り下げ済み（withdrawn）でも、取得した人が使い続けている間は、権利侵害などで停止できる
    if (pub.status !== "approved" && pub.status !== "withdrawn") {
      throw new ReviewError("failed-precondition", "このパックは、配信を停止できる状態ではありません。");
    }
    const sub = await tx.findSubmission(packId, pub.version);
    tx.suspendPublicPack(packId);
    if (sub) {
      tx.updateSubmission(sub.id, {
        status: "suspended",
        decisionNote: reason,
        decidedBy: input.adminUid,
      });
    }
    tx.addNotice(pub.creatorId, {
      kind: NOTICE_KINDS.suspended,
      packId,
      content: suspendedCreatorNoticeText(pub.name, reason),
    });
    return { pub, changed: true };
  });

  // 取得した人へ。公開用の素材は残す。停止済みの再実行でも、書き直す（文書 ID が同じなので重ならない）
  const uids = await store.listOwnerUids(packId);
  const notice: Notice = {
    kind: NOTICE_KINDS.suspended,
    packId,
    content: suspendedOwnerNoticeText(outcome.pub.name),
    id: ownerSuspendNoticeId(packId),
  };
  for (let i = 0; i < uids.length; i += NOTICE_CHUNK_SIZE) {
    await store.writeNoticeBatch(uids.slice(i, i + NOTICE_CHUNK_SIZE), notice);
  }
  return {
    packId,
    creatorId: outcome.pub.creatorId,
    status: "suspended",
    notifiedOwners: uids.length,
    changed: outcome.changed,
  };
}
