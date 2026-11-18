/// 通話の記録（`contentType: "call"`）の結果の判定（2026-11-18）。Firestore非依存の純関数。

export type CallRecordResult = "completed" | "missed" | "cancelled";

/** 広場の通話で、呼び出し中に始めた人が切った（キャンセル）とみなす最大の経過時間。
 * クライアントの呼び出し時間（30秒）に、書き込みの遅れの余裕を足したもの。 */
export const GROUP_CALL_CANCEL_WINDOW_MS = 35 * 1000;

/**
 * 一対の通話が終わった時の結果。応答後に終わったら通話、応答前に発信側が切った
 * （`ringing`→`ended`）ならキャンセル、それ以外（拒否・時間切れ）は不在着信。
 */
export function dmCallRecordResult(
  beforeStatus: unknown,
  afterStatus: unknown,
): CallRecordResult {
  if (beforeStatus === "active" && afterStatus === "ended") return "completed";
  if (beforeStatus === "ringing" && afterStatus === "ended") return "cancelled";
  return "missed";
}

/**
 * 広場の通話が終わった時の結果。始めた人以外が入らなかった通話は、呼び出しの間
 * （[GROUP_CALL_CANCEL_WINDOW_MS]以内）に終わればキャンセル、それ以降は不在着信。
 * `joinedUserIds`を持たない古い通話は、不在着信と決めつけず通話として扱う。
 */
export function groupCallRecordResult(params: {
  joinedUserIds: unknown;
  initiatorId: string;
  createdAtMs: number | null;
  endedAtMs: number;
}): CallRecordResult {
  const { joinedUserIds, initiatorId, createdAtMs, endedAtMs } = params;
  const nobodyJoined =
    Array.isArray(joinedUserIds) &&
    joinedUserIds.every((id) => id === initiatorId);
  if (!nobodyJoined) return "completed";
  if (createdAtMs !== null && endedAtMs - createdAtMs <= GROUP_CALL_CANCEL_WINDOW_MS) {
    return "cancelled";
  }
  return "missed";
}
