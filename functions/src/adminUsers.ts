/**
 * 管理画面の住人管理（一括停止・プロフィール確認の記録、2026-10-10追加）の
 * 純粋なロジック。Firestore・認証には依存させず、単体テスト
 * （`adminUsers.test.ts`）できる形にしてある。
 */

/** 1回の一括停止/解除で扱える最大件数。 */
export const BULK_SUSPEND_MAX = 100;

/** プロフィール確認の理由（記録用の列挙値）。 */
export const PROFILE_VIEW_REASONS = ["report", "investigation", "other"] as const;
export type ProfileViewReason = (typeof PROFILE_VIEW_REASONS)[number];

/** プロフィール確認の補足の最大文字数。 */
export const PROFILE_VIEW_NOTE_MAX_LENGTH = 200;

export type SkipReason =
  | "invalid"
  | "duplicate"
  | "self"
  | "not-found"
  | "pending-deletion"
  | "admin";

export interface SkippedTarget {
  id: string;
  reason: SkipReason;
}

export type NormalizedTargets =
  | { ok: true; ids: string[]; skipped: SkippedTarget[] }
  | { ok: false; reason: string };

/**
 * 一括操作の対象idを検証して整える。配列でない・空・上限超過はエラー。
 * 自分自身・重複・不正な値は対象から外し、理由つきで`skipped`に返す。
 */
export function normalizeBulkTargets(
  raw: unknown,
  selfUid: string,
): NormalizedTargets {
  if (!Array.isArray(raw) || raw.length === 0) {
    return { ok: false, reason: "targetUserIdsが必要です" };
  }
  if (raw.length > BULK_SUSPEND_MAX) {
    return {
      ok: false,
      reason: `一度に操作できるのは${BULK_SUSPEND_MAX}件までです`,
    };
  }
  const ids: string[] = [];
  const skipped: SkippedTarget[] = [];
  const seen = new Set<string>();
  for (const value of raw) {
    if (typeof value !== "string" || value.length === 0 || value.length > 128) {
      skipped.push({ id: String(value), reason: "invalid" });
    } else if (seen.has(value)) {
      skipped.push({ id: value, reason: "duplicate" });
    } else if (value === selfUid) {
      seen.add(value);
      skipped.push({ id: value, reason: "self" });
    } else {
      seen.add(value);
      ids.push(value);
    }
  }
  return { ok: true, ids, skipped };
}

/**
 * 読み込んだ対象ユーザーの状態から、この操作を行ってよいかを判定する。
 * 行ってはいけない場合はスキップ理由、行ってよければnullを返す。
 * [data]はユーザードキュメント（存在しなければundefined）、[isAdmin]は
 * 対象が管理者クレームを持つか（停止時のみ判定に使う）。
 */
export function classifyTarget(
  data: { accountStatus?: unknown } | undefined,
  suspend: boolean,
  isAdmin: boolean,
): SkipReason | null {
  if (!data) return "not-found";
  if (data.accountStatus === "pendingDeletion") return "pending-deletion";
  if (suspend && isAdmin) return "admin";
  return null;
}

export type ProfileViewRequest =
  | { ok: true; targetUserId: string; reason: ProfileViewReason; note: string }
  | { ok: false; reason: string };

/** プロフィール確認の記録リクエスト（対象・理由・補足）を検証する。 */
export function parseProfileViewRequest(data: unknown): ProfileViewRequest {
  if (typeof data !== "object" || data === null) {
    return { ok: false, reason: "リクエストが不正です" };
  }
  const { targetUserId, reason, note } = data as Record<string, unknown>;
  if (typeof targetUserId !== "string" || targetUserId.length === 0) {
    return { ok: false, reason: "targetUserIdが必要です" };
  }
  if (
    typeof reason !== "string" ||
    !(PROFILE_VIEW_REASONS as readonly string[]).includes(reason)
  ) {
    return { ok: false, reason: "理由を選択してください" };
  }
  if (note !== undefined && typeof note !== "string") {
    return { ok: false, reason: "補足は文字列で指定してください" };
  }
  const trimmed = (note ?? "").trim();
  if (trimmed.length > PROFILE_VIEW_NOTE_MAX_LENGTH) {
    return {
      ok: false,
      reason: `補足は${PROFILE_VIEW_NOTE_MAX_LENGTH}文字以内にしてください`,
    };
  }
  return {
    ok: true,
    targetUserId,
    reason: reason as ProfileViewReason,
    note: trimmed,
  };
}
