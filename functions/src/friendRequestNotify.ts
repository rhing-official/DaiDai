/** 友達申請の新着通知の宛先・本文の決定（2026-10-13追加）。Firestore非依存の純関数。 */

export interface FriendRequestDoc {
  status?: unknown;
  fromUserId?: unknown;
  toUserId?: unknown;
  message?: unknown;
}

/** 通知本文の定型部分（サーバーが書く文言のためクライアントの言語設定は反映できない）。 */
export const FRIEND_REQUEST_BODY = "友達申請が届きました";

/**
 * 通知する宛先を返す。新規・却下後の再申請（statusがpending以外からpendingへ）
 * のみ対象で、承認・取り消し・変化なしでは送らない。宛先は申請を受ける側だけ。
 */
export function resolveFriendRequestRecipient(
  before: FriendRequestDoc | undefined,
  after: FriendRequestDoc | undefined,
): { recipientId: string; senderId: string } | null {
  if (after?.status !== "pending" || before?.status === "pending") return null;
  const senderId = after.fromUserId;
  const recipientId = after.toUserId;
  if (typeof senderId !== "string" || typeof recipientId !== "string") return null;
  if (!senderId || !recipientId || senderId === recipientId) return null;
  return { recipientId, senderId };
}

/** 本文。申請に添えられたメッセージ（最大100文字）があれば続けて表示する。 */
export function friendRequestBody(message: unknown): string {
  const text = typeof message === "string" ? message.trim() : "";
  return text ? `${FRIEND_REQUEST_BODY}：${text}` : FRIEND_REQUEST_BODY;
}
