/**
 * 語らい内の画像・動画の保存期間（2026-11-28、ユーザー決定）。無料は30日、極みは180日。
 * アルバムに入れたものは、別のパスへコピー済みなので、ここでは触らない。
 * Firebase固有の部分（Storageの削除、メッセージの更新）は[RetentionStore]に分け、
 * 判断だけをここに置く（`draftFileCleanup.ts`と同じ作り）。
 */

export const FREE_RETENTION_DAYS = 30;
export const KIWAMI_RETENTION_DAYS = 180;

const DAY_MS = 24 * 60 * 60 * 1000;

/** 1回の掃除で期限切れにするメッセージ数の上限。残りは翌日に回す。 */
export const RETENTION_EXPIRE_LIMIT = 500;

/** 送信日時から、期限（ミリ秒）を決める。送信者が極みなら180日、それ以外は30日。 */
export function retentionExpiresAtMs(sentAtMs: number, isKiwami: boolean): number {
  return sentAtMs + (isKiwami ? KIWAMI_RETENTION_DAYS : FREE_RETENTION_DAYS) * DAY_MS;
}

/**
 * 既存のメッセージ（この仕組みの前に送られたもの）の期限。通常の期限と、予告の日から
 * 無料の日数が過ぎた日の、遅いほう。予告の前に送られた画像が、予告から30日は残るようにする。
 */
export function legacyExpiresAtMs(
  sentAtMs: number,
  isKiwami: boolean,
  noticeAtMs: number,
): number {
  return Math.max(
    retentionExpiresAtMs(sentAtMs, isKiwami),
    noticeAtMs + FREE_RETENTION_DAYS * DAY_MS,
  );
}

type AttachmentLike = { extension?: unknown; playbackPath?: unknown };

export type ChatMessageData = {
  fileMetadata?: AttachmentLike | null;
  attachments?: AttachmentLike[] | null;
  [key: string]: unknown;
};

export type ConversationRef = { kind: "dm" | "group"; id: string; messageId: string };

/** メッセージの文書パスから、会話の種類・id・メッセージidを取り出す。チャット以外はnull。 */
export function conversationFromDocPath(docPath: string): ConversationRef | null {
  const m = /^(directMessages|groups)\/([^/]+)\/rooms\/[^/]+\/messages\/([^/]+)$/.exec(docPath);
  if (!m) return null;
  return { kind: m[1] === "directMessages" ? "dm" : "group", id: m[2]!, messageId: m[3]! };
}

/** 添付ファイルを持つメッセージか（ぺったん・通知カード・通話の記録などは対象外）。 */
export function hasExpirableAttachment(message: ChatMessageData | undefined): boolean {
  if (!message) return false;
  if (Array.isArray(message.attachments) && message.attachments.length > 0) return true;
  return !!message.fileMetadata;
}

function cleanExtension(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const ext = value.replace(/^\./, "").trim();
  return ext.length > 0 && !ext.includes("/") ? ext : null;
}

/**
 * メッセージの添付が置かれているStorageのパスを全て挙げる。`storagePath`は保存していない為、
 * 保存の規約（`dmFiles|groupFiles/{id}/{messageId}.ext`、複数添付は`.../{messageId}/{index}.ext`）から
 * 組み立てる。それぞれに、サムネイル（`_thumb.jpg`）と再生用の動画（`_play.mp4`）も加える。
 */
export function attachmentStoragePaths(
  message: ChatMessageData,
  conv: ConversationRef,
): string[] {
  const prefix = conv.kind === "dm" ? "dmFiles" : "groupFiles";
  const base = `${prefix}/${conv.id}/${conv.messageId}`;
  const out = new Set<string>();
  const addFamily = (stem: string, ext: string | null, playbackPath: unknown) => {
    if (ext) out.add(`${stem}.${ext}`);
    out.add(`${stem}_thumb.jpg`);
    out.add(`${stem}_play.mp4`);
    if (typeof playbackPath === "string" && playbackPath.length > 0) out.add(playbackPath);
  };
  const attachments = Array.isArray(message.attachments) ? message.attachments : [];
  if (attachments.length > 0) {
    attachments.forEach((a, i) => addFamily(`${base}/${i}`, cleanExtension(a.extension), a.playbackPath));
  } else if (message.fileMetadata) {
    addFamily(base, cleanExtension(message.fileMetadata.extension), message.fileMetadata.playbackPath);
  }
  return [...out];
}

export interface RetentionStore {
  /** Storageのファイルを消す。無くてもエラーにしない。 */
  deleteFile(path: string): Promise<void>;
  /** メッセージに「添付が期限切れ」の印を付け、期限（`expiresAt`）を消す。 */
  markExpired(docPath: string): Promise<void>;
}

export type ExpiredMessage = { docPath: string; data: ChatMessageData };

/** メッセージの添付ファイルを全て消す。1件でも失敗したら、失敗したパスを返す。 */
export async function deleteMessageAttachments(
  store: Pick<RetentionStore, "deleteFile">,
  docPath: string,
  data: ChatMessageData,
): Promise<{ deleted: string[]; failed: string[] }> {
  const conv = conversationFromDocPath(docPath);
  const deleted: string[] = [];
  const failed: string[] = [];
  if (!conv) return { deleted, failed };
  for (const path of attachmentStoragePaths(data, conv)) {
    try {
      await store.deleteFile(path);
      deleted.push(path);
    } catch {
      failed.push(path);
    }
  }
  return { deleted, failed };
}

export type ExpireResult = {
  /** 添付を消して、印を付けたメッセージの文書パス。 */
  expired: string[];
  /** 消せなかった（明日、もう一度試す）メッセージの文書パス。 */
  failed: string[];
  /** 消さずに、数えただけか。 */
  dryRun: boolean;
  /** 消す予定だったメッセージの件数（dryRunの時）。 */
  wouldExpire: number;
};

/**
 * 期限を過ぎたメッセージの添付を消す。[deleteEnabled]が偽の時は、何も消さず、件数だけ返す
 * （最初は件数を確かめてから有効にする為）。1メッセージで1件でも消せなければ、印を付けず、
 * 翌日にもう一度試す。
 */
export async function expireMessageAttachments(
  store: RetentionStore,
  messages: ExpiredMessage[],
  deleteEnabled: boolean,
  limit: number = RETENTION_EXPIRE_LIMIT,
): Promise<ExpireResult> {
  const target = messages.filter((m) => hasExpirableAttachment(m.data)).slice(0, limit);
  if (!deleteEnabled) {
    return { expired: [], failed: [], dryRun: true, wouldExpire: target.length };
  }
  const expired: string[] = [];
  const failed: string[] = [];
  for (const m of target) {
    const { failed: failedFiles } = await deleteMessageAttachments(store, m.docPath, m.data);
    if (failedFiles.length > 0) {
      failed.push(m.docPath);
      continue;
    }
    try {
      await store.markExpired(m.docPath);
      expired.push(m.docPath);
    } catch {
      failed.push(m.docPath);
    }
  }
  return { expired, failed, dryRun: false, wouldExpire: 0 };
}
