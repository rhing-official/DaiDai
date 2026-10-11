import '../models/app_user.dart';
import '../models/group.dart';
import '../models/group_role.dart';
import 'group_permissions.dart';
import 'mention_suggestion.dart';

/// 呼び名（無ければRhing Seed）。`@`サジェストの表示名・本文へ挿入する名前に使う。
String _mentionLabelOf(AppUser user, String? conversationId) {
  final nickname = user.effectiveNicknameFor(conversationId)?.text;
  if (nickname != null && nickname.trim().isNotEmpty) return nickname.trim();
  return user.rhingSeed;
}

MentionCandidate _userCandidate(AppUser user, String? conversationId) =>
    MentionCandidate(
      kind: MentionKind.user,
      id: user.userId,
      label: _mentionLabelOf(user, conversationId),
      subtitle: user.rhingSeed,
    );

/// 一対（DM）の候補は相手1人のメンバーのみ（ロール・@everyoneは無い）。
List<MentionCandidate> buildDmMentionCandidates({
  required AppUser? otherUser,
  required String conversationId,
}) {
  if (otherUser == null) return const [];
  return [_userCandidate(otherUser, conversationId)];
}

/// 広場の候補（2026-10-11追加）。メンバーは自分以外全員。`@everyone`・ロールは
/// `GroupPermission.mentionEveryone`を持つ場合のみ出す（長は常に可）。
/// 基準ロール（`isEveryone`）は`@everyone`と同じ意味なのでロール候補から除く。
List<MentionCandidate> buildGroupMentionCandidates({
  required Group group,
  required String currentUserId,
  required List<AppUser> members,
  required List<GroupRole> roles,
}) {
  final candidates = <MentionCandidate>[
    for (final m in members)
      if (m.userId != currentUserId) _userCandidate(m, group.groupId),
  ];
  final canMentionAll = hasGroupPermission(
    group: group,
    userId: currentUserId,
    permission: GroupPermission.mentionEveryone,
  );
  if (canMentionAll) {
    candidates.add(
      const MentionCandidate(
        kind: MentionKind.everyone,
        id: '',
        label: 'everyone',
      ),
    );
    for (final role in roles) {
      if (role.isEveryone) continue;
      candidates.add(
        MentionCandidate(
          kind: MentionKind.role,
          id: role.roleId,
          label: role.name,
          color: role.color,
        ),
      );
    }
  }
  return candidates;
}
