/** 一対のブロック（2026-10-11）。Firestore非依存の純関数。 */

/**
 * [recipientIds]のうち、[senderId]をブロックしている人を除いて返す。
 * [isBlocked]は「recipientIdが senderIdをブロックしているか」を答える。
 */
export async function excludeBlockers(
  recipientIds: string[],
  senderId: string,
  isBlocked: (recipientId: string, senderId: string) => Promise<boolean>,
): Promise<string[]> {
  const flags = await Promise.all(
    recipientIds.map((id) => isBlocked(id, senderId)),
  );
  return recipientIds.filter((_, i) => !flags[i]);
}
