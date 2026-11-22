/**
 * 住人による通報（メッセージ・住人・広場、2026-11-22追加）の純粋なロジック。
 * Firestore・認証には依存させず、単体テスト（`reports.test.ts`）できる形にしてある
 * （Firebase固有の部分は`index.ts`の`submitReport`等に置く。自前化の際に本体だけを
 * 別サーバーへ移せるようにするため）。
 *
 * 証拠はクライアントの申告を信用せず、通報を受けたサーバーが対象メッセージと前後の
 * メッセージを複写して保存する（`文書/将来/E2E暗号化.md`の「束にした形式」）。E2E暗号化へ
 * 移った後は、中身だけを「端末が提出する検証付きの証拠」に差し替える。
 */

/** 通報の対象の種類。 */
export const REPORT_TARGET_TYPES = ["message", "user", "group"] as const;
export type ReportTargetType = (typeof REPORT_TARGET_TYPES)[number];

/** 通報の理由（記録用の列挙値）。 */
export const REPORT_REASONS = [
  "harassment",
  "spam",
  "sexual",
  "violence",
  "illegal",
  "impersonation",
  "other",
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

/** 通報の補足の最大文字数。 */
export const REPORT_NOTE_MAX_LENGTH = 500;

/** 1人が24時間に出せる通報の最大件数（通報の乱用・運営への嫌がらせの抑止）。 */
export const REPORT_DAILY_LIMIT = 20;

/** 対象メッセージの前後に、証拠として添える件数。 */
export const REPORT_CONTEXT_BEFORE = 5;
export const REPORT_CONTEXT_AFTER = 5;

/** 処理の結果。`dismissed`＝問題なし、`actioned`＝対応済み。 */
export const REPORT_RESOLUTIONS = ["dismissed", "actioned"] as const;
export type ReportResolution = (typeof REPORT_RESOLUTIONS)[number];

/** 運営の処理の補足の最大文字数。 */
export const REPORT_RESOLUTION_NOTE_MAX_LENGTH = 500;

export interface ReportInput {
  targetType: ReportTargetType;
  reason: ReportReason;
  note: string;
  /** user: 通報する住人。message: 使わない（サーバーがメッセージから決める）。 */
  targetUserId?: string;
  /** group: 通報する広場。message（広場の会話）: 広場のid。 */
  groupId?: string;
  /** message（一対の会話）: 一対のid。 */
  dmId?: string;
  roomId?: string;
  messageId?: string;
}

export type ParsedReportInput =
  | { ok: true; input: ReportInput }
  | { ok: false; reason: string };

function readId(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  if (value.length === 0 || value.length > 256 || value.includes("/")) {
    return undefined;
  }
  return value;
}

/** callableの入力を検証して整える。 */
export function parseReportInput(data: unknown): ParsedReportInput {
  const d = (data ?? {}) as Record<string, unknown>;
  const targetType = d.targetType;
  if (
    typeof targetType !== "string" ||
    !(REPORT_TARGET_TYPES as readonly string[]).includes(targetType)
  ) {
    return { ok: false, reason: "targetTypeが不正です" };
  }
  const reason = d.reason;
  if (
    typeof reason !== "string" ||
    !(REPORT_REASONS as readonly string[]).includes(reason)
  ) {
    return { ok: false, reason: "reasonが不正です" };
  }
  const rawNote = d.note;
  if (rawNote !== undefined && rawNote !== null && typeof rawNote !== "string") {
    return { ok: false, reason: "noteが不正です" };
  }
  const note = (rawNote ?? "").toString().trim();
  if (note.length > REPORT_NOTE_MAX_LENGTH) {
    return {
      ok: false,
      reason: `補足は${REPORT_NOTE_MAX_LENGTH}文字までです`,
    };
  }
  const input: ReportInput = {
    targetType: targetType as ReportTargetType,
    reason: reason as ReportReason,
    note,
  };
  if (targetType === "user") {
    const targetUserId = readId(d.targetUserId);
    if (!targetUserId) return { ok: false, reason: "targetUserIdが必要です" };
    input.targetUserId = targetUserId;
  } else if (targetType === "group") {
    const groupId = readId(d.groupId);
    if (!groupId) return { ok: false, reason: "groupIdが必要です" };
    input.groupId = groupId;
  } else {
    const roomId = readId(d.roomId);
    const messageId = readId(d.messageId);
    const dmId = readId(d.dmId);
    const groupId = readId(d.groupId);
    if (!roomId || !messageId) {
      return { ok: false, reason: "roomIdとmessageIdが必要です" };
    }
    if ((dmId === undefined) === (groupId === undefined)) {
      return { ok: false, reason: "dmIdかgroupIdのどちらか一方が必要です" };
    }
    input.roomId = roomId;
    input.messageId = messageId;
    input.dmId = dmId;
    input.groupId = groupId;
  }
  return { ok: true, input };
}

/**
 * 同じ通報者が同じ対象を何度も通報して運営の画面を埋めないよう、通報の文書idを
 * 「通報者＋対象」から決める。同じidで2回目に作ろうとすると既存の通報になる。
 */
export function reportTargetKey(input: ReportInput): string {
  switch (input.targetType) {
    case "user":
      return `user:${input.targetUserId}`;
    case "group":
      return `group:${input.groupId}`;
    case "message":
      return `message:${input.dmId ?? input.groupId}:${input.roomId}:${input.messageId}`;
  }
}

/** 証拠に複写する、メッセージ1件分。 */
export interface EvidenceMessage {
  messageId: string;
  senderId: string;
  senderRhingSeed: string | null;
  content: string;
  contentType: string;
  /** ISO文字列。無ければnull。 */
  sentAt: string | null;
  /** 添付があれば、ファイル名・種類・サイズ・保存先のURL。 */
  attachments: {
    fileName: string;
    mimeType: string;
    sizeBytes: number;
    url: string;
  }[];
  /** 通報の対象になったメッセージか。 */
  isTarget: boolean;
}

/** 複写する本文の最大文字数（極端に長い本文で文書が大きくならないように）。 */
const EVIDENCE_CONTENT_MAX_LENGTH = 2000;

function readAttachments(data: Record<string, unknown>): EvidenceMessage["attachments"] {
  const out: EvidenceMessage["attachments"] = [];
  const push = (raw: unknown): void => {
    if (raw === null || typeof raw !== "object") return;
    const m = raw as Record<string, unknown>;
    if (typeof m.url !== "string") return;
    out.push({
      fileName: typeof m.fileName === "string" ? m.fileName : "",
      mimeType: typeof m.mimeType === "string" ? m.mimeType : "",
      sizeBytes: typeof m.sizeBytes === "number" ? m.sizeBytes : 0,
      url: m.url,
    });
  };
  push(data.fileMetadata);
  if (Array.isArray(data.attachments)) {
    for (const a of data.attachments) {
      push(a);
    }
  }
  return out.slice(0, 10);
}

/**
 * Firestoreのメッセージ文書のデータを、証拠の形へ写す。`sentAt`はTimestampでも
 * `toDate`を持つ値でも受ける（テストしやすいように、Firestoreの型には依存しない）。
 */
export function toEvidenceMessage(
  messageId: string,
  data: Record<string, unknown>,
  isTarget: boolean,
): EvidenceMessage {
  const sentAtRaw = data.sentAt as { toDate?: () => Date } | undefined;
  const sentAt =
    sentAtRaw && typeof sentAtRaw.toDate === "function"
      ? sentAtRaw.toDate().toISOString()
      : null;
  const content = typeof data.content === "string" ? data.content : "";
  return {
    messageId,
    senderId: typeof data.senderId === "string" ? data.senderId : "",
    senderRhingSeed:
      typeof data.senderRhingSeed === "string" ? data.senderRhingSeed : null,
    content: content.slice(0, EVIDENCE_CONTENT_MAX_LENGTH),
    contentType: typeof data.contentType === "string" ? data.contentType : "text",
    sentAt,
    attachments: readAttachments(data),
    isTarget,
  };
}

/** 24時間以内の通報の件数が上限に達しているか。 */
export function isOverDailyLimit(
  createdAtMillis: number[],
  nowMillis: number,
): boolean {
  const since = nowMillis - 24 * 60 * 60 * 1000;
  return createdAtMillis.filter((t) => t >= since).length >= REPORT_DAILY_LIMIT;
}

export interface ParsedResolution {
  resolution: ReportResolution;
  note: string;
}

export type ParsedResolutionResult =
  | { ok: true; value: ParsedResolution }
  | { ok: false; reason: string };

/** 運営の処理（却下／対応済み）の入力を検証する。 */
export function parseResolution(data: unknown): ParsedResolutionResult {
  const d = (data ?? {}) as Record<string, unknown>;
  const resolution = d.resolution;
  if (
    typeof resolution !== "string" ||
    !(REPORT_RESOLUTIONS as readonly string[]).includes(resolution)
  ) {
    return { ok: false, reason: "resolutionが不正です" };
  }
  const rawNote = d.note;
  if (rawNote !== undefined && rawNote !== null && typeof rawNote !== "string") {
    return { ok: false, reason: "noteが不正です" };
  }
  const note = (rawNote ?? "").toString().trim();
  if (note.length > REPORT_RESOLUTION_NOTE_MAX_LENGTH) {
    return {
      ok: false,
      reason: `補足は${REPORT_RESOLUTION_NOTE_MAX_LENGTH}文字までです`,
    };
  }
  return { ok: true, value: { resolution: resolution as ReportResolution, note } };
}
