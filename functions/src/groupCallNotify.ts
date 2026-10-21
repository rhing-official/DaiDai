/// 広場通話の開始を知らせるプッシュ通知の宛先・文面（2026-10-21追加）。
/// Firestore非依存の純関数。着信音は鳴らさず、通知だけを送る。

/** 通知する相手: 広場のメンバーから、通話を始めた本人を除く（重複は1回に）。 */
export function groupCallRecipients(
  memberIds: unknown,
  initiatorId: string,
): string[] {
  if (!Array.isArray(memberIds)) return [];
  const result: string[] = [];
  for (const id of memberIds) {
    if (typeof id !== "string" || id === initiatorId) continue;
    if (!result.includes(id)) result.push(id);
  }
  return result;
}

/** 本文。開始者の呼び名があれば先頭に付ける。映像通話なら「ビデオ通話」。 */
export function groupCallNotificationBody(
  initiatorName: string,
  isVideo: boolean,
): string {
  const kind = isVideo ? "ビデオ通話" : "通話";
  return initiatorName
    ? `${initiatorName}が${kind}を始めました`
    : `${kind}が始まりました`;
}
