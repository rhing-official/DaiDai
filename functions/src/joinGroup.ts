/** 承認不要の広場への参加判定（2026-10-11追加）。Firestore非依存の純関数。 */

export type JoinDecision = "denied" | "already-member" | "join";

export interface JoinGroupData {
  memberIds?: string[];
  /** falseの時だけ承認不要。欠落・その他は承認必須（既存データの互換）。 */
  requiresApproval?: boolean;
}

/** 承認必須なら拒否、既にメンバーなら何もしない、それ以外は参加させる。 */
export function decideJoin(group: JoinGroupData, uid: string): JoinDecision {
  if (group.requiresApproval !== false) return "denied";
  if ((group.memberIds ?? []).includes(uid)) return "already-member";
  return "join";
}

export interface RoleData {
  isEveryone?: boolean;
  permissions?: string[];
}

/** 新規メンバーの実効権限（全員に適用される基準ロールの権限のみ）。 */
export function newMemberPermissions(roles: RoleData[]): string[] {
  const everyone = roles.find((r) => r.isEveryone === true);
  return Array.isArray(everyone?.permissions) ? [...everyone!.permissions!] : [];
}
