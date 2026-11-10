// 送信予定のメッセージ（`scheduledMessages/{id}`）を、時刻になったら送る処理の純粋な判定部分
// （2026-11-10追加）。Firebase依存の本体は`index.ts`の`sendScheduledMessages`。

/** 予定できるのは、今から最大でこの日数先まで（1か月、ユーザー決定）。 */
export const SCHEDULED_MAX_DAYS = 31;

/** 失敗した予定を、一覧に残しておく日数（その後は自動で掃除する）。 */
export const SCHEDULED_FAILED_KEEP_DAYS = 7;

/** 1回の実行で処理する最大件数。 */
export const SCHEDULED_BATCH_LIMIT = 100;

/** 送れなかった理由（クライアントの一覧で文言に変換する）。 */
export type ScheduledFailReason =
  | "notMember"
  | "conversationMissing"
  | "invalid";

export interface ScheduledSendContext {
  scope: unknown;
  senderId: unknown;
  /** 一対の`participants`。 */
  dmParticipants?: string[] | null;
  /** 広場の`memberIds`。 */
  groupMemberIds?: string[] | null;
  /** 寄合の`memberIds`（一対の寄合は`participants`）。 */
  roomMemberIds?: string[] | null;
  /** 会話本体・寄合のドキュメントが存在するか。 */
  conversationExists: boolean;
  roomExists: boolean;
}

/** 予定した本人が、まだその会話・寄合に参加しているかを確かめ、送れなければ理由を返す。 */
export function scheduledSendFailure(
  ctx: ScheduledSendContext,
): ScheduledFailReason | null {
  if (typeof ctx.senderId !== "string" || ctx.senderId === "") return "invalid";
  if (ctx.scope !== "dm" && ctx.scope !== "group") return "invalid";
  if (!ctx.conversationExists || !ctx.roomExists) return "conversationMissing";
  if (ctx.scope === "dm") {
    return ctx.dmParticipants?.includes(ctx.senderId) ? null : "notMember";
  }
  if (!ctx.groupMemberIds?.includes(ctx.senderId)) return "notMember";
  if (!ctx.roomMemberIds?.includes(ctx.senderId)) return "notMember";
  return null;
}

/** 予定の日時が許される範囲か（作成時のルールと同じ。未来〜[SCHEDULED_MAX_DAYS]日後）。 */
export function isScheduledTimeInRange(sendAtMs: number, nowMs: number): boolean {
  const max = nowMs + SCHEDULED_MAX_DAYS * 24 * 60 * 60 * 1000;
  return sendAtMs > nowMs && sendAtMs <= max;
}

/** 失敗した予定を掃除してよいか。 */
export function isFailedScheduledExpired(
  failedAtMs: number,
  nowMs: number,
): boolean {
  return nowMs - failedAtMs >= SCHEDULED_FAILED_KEEP_DAYS * 24 * 60 * 60 * 1000;
}
