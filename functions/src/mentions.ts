/** `@`メンションの通知先の決定（2026-10-11追加）。Firestore非依存の純関数。 */

/** `@everyone`・ロール宛メンションに必要な権限（`GroupPermission.mentionEveryone`と同名）。 */
export const MENTION_EVERYONE_PERMISSION = "mentionEveryone";

export interface MentionInput {
  /** メッセージの`mentionedUserIds`/`mentionedRoleIds`/`mentionEveryone`。 */
  mentionedUserIds?: unknown;
  mentionedRoleIds?: unknown;
  mentionEveryone?: unknown;
}

export interface MentionContext {
  senderId: string;
  isDm: boolean;
  /** 一対はparticipants、広場はmemberIds（送信者を含んでよい）。 */
  memberIds: string[];
  /** 広場のみ。 */
  ownerId?: string;
  roleAssignments?: Record<string, string[]>;
  memberPermissions?: Record<string, string[]>;
}

function stringList(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string")
    : [];
}

/**
 * メッセージのメンション宛先（通知する人）を返す。有効なメンションが1つも
 * 残らなければnull（通常どおり全員へ通知する）。クライアントが付けた値は
 * そのまま信用せず、ここで再検証する:
 * - 個人宛: その会話のメンバー（送信者自身を除く）のみ有効
 * - `@everyone`・ロール宛: 広場で、送信者が長または`mentionEveryone`権限を
 *   持つ場合のみ有効（一対では常に無効）
 */
export function resolveMentionRecipients(
  input: MentionInput,
  ctx: MentionContext,
): string[] | null {
  const pool = new Set(ctx.memberIds.filter((id) => id !== ctx.senderId));
  const result = new Set<string>();

  for (const id of stringList(input.mentionedUserIds)) {
    if (pool.has(id)) result.add(id);
  }

  const canMentionAll =
    !ctx.isDm &&
    (ctx.ownerId === ctx.senderId ||
      (ctx.memberPermissions?.[ctx.senderId] ?? []).includes(
        MENTION_EVERYONE_PERMISSION,
      ));
  if (canMentionAll) {
    if (input.mentionEveryone === true) {
      for (const id of pool) result.add(id);
    }
    const roleIds = new Set(stringList(input.mentionedRoleIds));
    if (roleIds.size > 0) {
      for (const [userId, assigned] of Object.entries(
        ctx.roleAssignments ?? {},
      )) {
        if (pool.has(userId) && assigned.some((r) => roleIds.has(r))) {
          result.add(userId);
        }
      }
    }
  }

  return result.size === 0 ? null : [...result];
}
