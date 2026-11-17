/// 出品済みパックの削除（申請→運営の承認→日時を指定して自動削除）の、画面・DBに依存しない部分
/// （2026-11-17）。検証・状態の遷移・入手した人へのお知らせの定型文を、ここにまとめる。

/** 申請の理由・却下の理由の最大文字数。 */
export const PACK_DELETION_TEXT_MAX = 200;

/** 承認から削除までに空ける最短の時間（周知の期間）。 */
export const PACK_DELETION_MIN_NOTICE_MS = 24 * 60 * 60 * 1000;

/** 削除の日時に指定できる、最も先の日時（今から）。 */
export const PACK_DELETION_MAX_AHEAD_MS = 366 * 24 * 60 * 60 * 1000;

export const PACK_DELETION_STATUSES = [
  "pending", // 申請中
  "scheduled", // 承認済み・削除待ち
  "completed", // 削除済み
  "rejected", // 却下
  "cancelled", // 取り消し
  "failed", // 削除に失敗
] as const;
export type PackDeletionStatus = (typeof PACK_DELETION_STATUSES)[number];

const TRANSITIONS: Record<PackDeletionStatus, PackDeletionStatus[]> = {
  pending: ["scheduled", "rejected"],
  scheduled: ["completed", "cancelled", "failed"],
  completed: [],
  rejected: [], // 却下後の再申請は、新しい申請として上書きする
  cancelled: [],
  failed: ["scheduled", "completed"], // 運営が日時を決め直す・手動で消した
};

export function canTransition(
  from: PackDeletionStatus,
  to: PackDeletionStatus,
): boolean {
  return TRANSITIONS[from].includes(to);
}

export type Validated<T> = { ok: true; value: T } | { ok: false; message: string };

/** 申請・却下の理由。前後の空白を除き、1〜200文字。 */
export function validateDeletionText(
  value: unknown,
  label: string,
  { required }: { required: boolean },
): Validated<string> {
  if (value === undefined || value === null || value === "") {
    return required
      ? { ok: false, message: `${label}を入力してください` }
      : { ok: true, value: "" };
  }
  if (typeof value !== "string") {
    return { ok: false, message: `${label}が正しくありません` };
  }
  const text = value.trim();
  if (text === "") {
    return required
      ? { ok: false, message: `${label}を入力してください` }
      : { ok: true, value: "" };
  }
  if (text.length > PACK_DELETION_TEXT_MAX) {
    return {
      ok: false,
      message: `${label}は${PACK_DELETION_TEXT_MAX}文字以内にしてください`,
    };
  }
  return { ok: true, value: text };
}

/** 削除の日時（ISO文字列かミリ秒）。今から24時間以上先で、1年以内。 */
export function validateDeleteAt(
  value: unknown,
  now: Date,
): Validated<Date> {
  let date: Date;
  if (typeof value === "number") date = new Date(value);
  else if (typeof value === "string") date = new Date(value);
  else return { ok: false, message: "削除する日時を指定してください" };
  if (Number.isNaN(date.getTime())) {
    return { ok: false, message: "削除する日時が正しくありません" };
  }
  const diff = date.getTime() - now.getTime();
  if (diff < PACK_DELETION_MIN_NOTICE_MS) {
    return {
      ok: false,
      message: "削除する日時は、今から24時間以上先にしてください（利用者へ知らせる期間のため）",
    };
  }
  if (diff > PACK_DELETION_MAX_AHEAD_MS) {
    return { ok: false, message: "削除する日時は、1年以内にしてください" };
  }
  return { ok: true, value: date };
}

/** 日本時間の「何月何日何時（何分）」。分が0なら省く。 */
export function formatJapanDateTime(date: Date): string {
  const parts = new Intl.DateTimeFormat("ja-JP", {
    timeZone: "Asia/Tokyo",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(date);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  const minute = get("minute");
  const time = minute === 0 ? `${get("hour")}時` : `${get("hour")}時${minute}分`;
  return `${get("month")}月${get("day")}日${time}`;
}

/** そのぺったんを入手した人へのお知らせの定型文。 */
export function packDeletionNoticeText(packName: string, deleteAt: Date): string {
  return `「${packName}」というぺったんをお使いの利用者の方に連絡します。${formatJapanDateTime(deleteAt)}に使えなくなります。`;
}
