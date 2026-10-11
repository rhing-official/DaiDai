/** プッシュ通知の表示用の整形（2026-10-11追加）。Firestore非依存の純関数。 */

/** [ms]（epoch ms）を日本時間の`HH:mm`（24時間表記）にする。 */
export function formatJstTime(ms: number): string {
  return new Intl.DateTimeFormat("ja-JP", {
    timeZone: "Asia/Tokyo",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(ms));
}

/** 本文の先頭に送信時刻を付ける（`14:32｜本文`）。Webの通知はFCMが自動表示する
 * ため、表示時点での整形ができない（日付・年の出し分けはAndroidのみ）。 */
export function withSentTime(body: string, ms: number): string {
  return `${formatJstTime(ms)}｜${body}`;
}

/** 広場の通知はアイコンが送信者のものなので、誰が送ったか分かるよう本文の先頭に
 * 送信者名を付ける（`山田: 本文`）。名前が空なら付けない。 */
export function withSenderName(body: string, senderName: string): string {
  return senderName ? `${senderName}: ${body}` : body;
}
