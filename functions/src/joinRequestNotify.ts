/** 広場の参加リクエスト通知の宛先決定（2026-10-11追加）。Firestore非依存の純関数。 */

/** 参加リクエストの承認・却下に必要な権限（`GroupPermission.manageJoinRequests`と同名）。 */
export const MANAGE_JOIN_REQUESTS_PERMISSION = "manageJoinRequests";

export interface JoinRequestGroup {
  ownerId?: string;
  memberIds?: string[];
  memberPermissions?: Record<string, string[]>;
}

/**
 * 参加リクエストを知らせる相手を返す。長（常に全権限）と`manageJoinRequests`
 * を持つメンバーのみ。申請者本人は（万一メンバーでも）除く。
 */
export function resolveJoinRequestRecipients(
  group: JoinRequestGroup,
  requesterId: string,
): string[] {
  const memberIds = Array.isArray(group.memberIds) ? group.memberIds : [];
  const recipients = new Set<string>();
  if (group.ownerId) recipients.add(group.ownerId);
  for (const id of memberIds) {
    const permissions = group.memberPermissions?.[id];
    if (
      Array.isArray(permissions) &&
      permissions.includes(MANAGE_JOIN_REQUESTS_PERMISSION)
    ) {
      recipients.add(id);
    }
  }
  recipients.delete(requesterId);
  return [...recipients];
}

/** 再申請は`status`がpending以外からpendingへ戻る更新。新規作成も対象。 */
export function isNewPendingRequest(
  before: { status?: unknown } | undefined,
  after: { status?: unknown } | undefined,
): boolean {
  return after?.status === "pending" && before?.status !== "pending";
}
