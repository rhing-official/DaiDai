/// メッセージの送信取消（ドキュメントの削除）を、出ている通知を閉じるために端末へ伝える
/// 合図の宛先・内容（2026-11-15追加）。Firestore非依存の純関数。

/** 合図を送る相手: 会話の参加者から、メッセージの送信者を除く（重複は1回に）。 */
export function recallRecipients(
  participantIds: unknown,
  senderId: unknown,
): string[] {
  if (!Array.isArray(participantIds)) return [];
  const result: string[] = [];
  for (const id of participantIds) {
    if (typeof id !== "string" || id === senderId) continue;
    if (!result.includes(id)) result.push(id);
  }
  return result;
}

/** データだけのFCMの中身。クライアント（`lib/push_notifications.dart`・
 * `web/firebase-messaging-sw.js`）が`type`で判定して、該当の通知を閉じる。 */
export function recallPayload(params: {
  conversationId: string;
  roomId: string;
  messageId: string;
}): Record<string, string> {
  return {
    type: "message_recalled",
    conversationId: params.conversationId,
    roomId: params.roomId,
    messageId: params.messageId,
  };
}
