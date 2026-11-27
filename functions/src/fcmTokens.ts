/** FCMトークンの一覧の扱い（2026-11-27）。Firestore非依存の純関数。 */

export type FcmTokenEntry = { token: string; platform: string };

/**
 * 旧保存先の一覧[legacy]と`private/fcm`の一覧[current]を、トークンの重複を除いて1つにする。
 * `muted: true`（この端末では、このアカウント宛ての通知を止めている）のトークンは除く。
 * 通知・お便り・通話の着信・送信取消の全ての送信が、ここを通るため、ここで除けば全ての
 * 通知が止まる。`muted`が無い古い登録は、止めていない扱い。同じトークンが両方に有って
 * 食い違う時は、`private/fcm`（新しい保存先）を正とする。
 */
export function mergeFcmTokenEntries(
  legacy: unknown,
  current: unknown,
): FcmTokenEntry[] {
  const merged = new Map<string, FcmTokenEntry>();
  const muted = new Set<string>();
  for (const list of [legacy, current]) {
    if (!Array.isArray(list)) continue;
    for (const e of list) {
      if (e && typeof e.token === "string" && typeof e.platform === "string") {
        merged.set(e.token, { token: e.token, platform: e.platform });
        if (e.muted === true) muted.add(e.token);
        else muted.delete(e.token);
      }
    }
  }
  for (const token of muted) merged.delete(token);
  return [...merged.values()];
}
