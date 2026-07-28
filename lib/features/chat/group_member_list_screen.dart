import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_join_request.dart';
import '../../models/group_role.dart';
import '../../providers/repository_providers.dart';
import '../../utils/group_permissions.dart';
import 'user_profile_card_dialog.dart';

/// 広場のメンバー一覧（ポップアップの中身）。manageJoinRequests権限を持つ
/// メンバーには、招待リンクからの参加リクエストの承認・却下UIもあわせて
/// 表示する。メンバー本体を先に、招待中（承認待ち）は最下部にまとめて表示する。
/// manageRoles権限を持つメンバーには、各メンバーへのカスタムロールの複数付与
/// （2026-07-28更新: 1人1ロールから複数付与に変更）もあわせて出す。長のみ、
/// 他メンバーへの長の譲渡ができる。
class GroupMemberListPopup extends ConsumerWidget {
  const GroupMemberListPopup({
    required this.currentUser,
    required this.group,
    required this.roles,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  /// この広場のカスタムロール一覧（呼び出し側で既にwatch済みのものを渡す）。
  final List<GroupRole> roles;

  Future<void> _showRolePicker(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    AppUser member,
    List<String> assignedRoleIds,
  ) async {
    final regularRoles = roles.where((r) => !r.isEveryone).toList();
    final groupRepository = ref.read(groupRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(strings.groupRolePickerTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (regularRoles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(strings.groupRoleListEmpty),
                    ),
                  for (final role in regularRoles)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: assignedRoleIds.contains(role.roleId),
                      secondary: CircleAvatar(
                        radius: 8,
                        backgroundColor: role.color != null
                            ? Color(0xFF000000 | role.color!)
                            : Colors.transparent,
                      ),
                      title: Text(role.name),
                      onChanged: (checked) async {
                        if (checked ?? false) {
                          assignedRoleIds.add(role.roleId);
                          await groupRepository.assignRole(
                            groupId: group.groupId,
                            userId: member.userId,
                            roleId: role.roleId,
                          );
                        } else {
                          assignedRoleIds.remove(role.roleId);
                          await groupRepository.unassignRole(
                            groupId: group.groupId,
                            userId: member.userId,
                            roleId: role.roleId,
                          );
                        }
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.save),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmTransferOwnership(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    AppUser member,
  ) async {
    final label = member.effectiveNickname?.text.isNotEmpty ?? false
        ? member.effectiveNickname!.text
        : '@${member.rhingId}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.groupTransferOwnershipConfirmTitle(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.groupTransferOwnershipConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(groupRepositoryProvider).transferOwnership(
            groupId: group.groupId,
            newOwnerId: member.userId,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final isOwner = group.ownerId == currentUser.userId;
    final canManageRoles = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageRoles,
    );
    final canManageJoinRequests = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageJoinRequests,
    );
    final groupRepository = ref.read(groupRepositoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.groupMemberListTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _SectionHeader(strings.groupMemberListMembersSection),
              FutureBuilder<List<AppUser>>(
                future: ref.read(userRepositoryProvider).getUsersByIds(group.memberIds),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final members = [...snapshot.data!]
                    ..sort((a, b) => a.rhingId.compareTo(b.rhingId));
                  return Column(
                    children: [
                      for (final member in members)
                        _MemberTile(
                          currentUser: currentUser,
                          user: member,
                          isOwner: member.userId == group.ownerId,
                          vocab: vocab,
                          strings: strings,
                          customRoles: roles,
                          assignedRoleIds: group.roleAssignments[member.userId] ??
                              const <String>[],
                          canManageRoles: canManageRoles,
                          onEditRoles: !canManageRoles
                              ? null
                              : () => _showRolePicker(
                                    context,
                                    ref,
                                    strings,
                                    member,
                                    [
                                      ...?group.roleAssignments[member.userId],
                                    ],
                                  ),
                          canTransferOwnership:
                              isOwner && member.userId != currentUser.userId,
                          onTransferOwnership: () => _confirmTransferOwnership(
                            context,
                            ref,
                            strings,
                            member,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (canManageJoinRequests) ...[
                const Divider(height: 24),
                _SectionHeader(strings.groupMemberListPendingSection),
                StreamBuilder<List<GroupJoinRequest>>(
                  stream: groupRepository.watchJoinRequests(group.groupId),
                  builder: (context, snapshot) {
                    final requests = snapshot.data ?? const [];
                    if (requests.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        for (final request in requests)
                          _JoinRequestTile(request: request, strings: strings),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _JoinRequestTile extends ConsumerWidget {
  const _JoinRequestTile({required this.request, required this.strings});

  final GroupJoinRequest request;
  final Strings strings;

  // 以前はawaitもエラーハンドリングも無い投げっぱなしで、失敗しても
  // ボタンの見た目だけが反応して何も起きていないように見えた（承認・却下が
  // 実は失敗していても気付けなかった）。エラー時は画面に表示する。
  Future<void> _respond(BuildContext context, WidgetRef ref, bool accept) async {
    try {
      await ref
          .read(groupRepositoryProvider)
          .respondToJoinRequest(request: request, accept: accept);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.person_add_alt_1_outlined),
      title: Text('@${request.requesterRhingId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _respond(context, ref, false),
            child: Text(strings.friendRequestDecline),
          ),
          FilledButton(
            onPressed: () => _respond(context, ref, true),
            child: Text(strings.friendRequestAccept),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.currentUser,
    required this.user,
    required this.isOwner,
    required this.vocab,
    required this.strings,
    required this.customRoles,
    required this.assignedRoleIds,
    required this.canManageRoles,
    required this.onEditRoles,
    required this.canTransferOwnership,
    required this.onTransferOwnership,
  });

  final AppUser currentUser;
  final AppUser user;

  /// このユーザーが長（[Group.ownerId]）かどうか。
  final bool isOwner;
  final Vocabulary vocab;
  final Strings strings;

  /// このユーザーが選べるカスタムロールの一覧（2026-07-28更新: 権限付き）。
  final List<GroupRole> customRoles;

  /// 現在付与されているロールidのリスト（複数可、2026-07-28更新）。
  final List<String> assignedRoleIds;

  /// manageRoles権限を持つメンバーのみtrue。falseの場合、ロールチップは
  /// タップ不可の表示専用になる。
  final bool canManageRoles;
  final VoidCallback? onEditRoles;

  /// 長のみ、自分以外のメンバーに対してtrue。
  final bool canTransferOwnership;
  final VoidCallback onTransferOwnership;

  @override
  Widget build(BuildContext context) {
    final iconUrl = user.effectiveIcon?.url;
    final nickname = user.effectiveNickname?.text;
    final label = (nickname?.isNotEmpty ?? false) ? nickname! : '@${user.rhingId}';
    final assignedRoles =
        customRoles.where((r) => assignedRoleIds.contains(r.roleId)).toList();
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        child: iconUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(label),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOwner) Chip(label: Text(vocab.owner)),
              if (canTransferOwnership)
                IconButton(
                  icon: const Icon(Icons.workspace_premium_outlined),
                  tooltip: strings.groupTransferOwnershipMenuItem,
                  onPressed: onTransferOwnership,
                ),
            ],
          ),
          const SizedBox(height: 4),
          ActionChip(
            avatar: assignedRoles.isNotEmpty && assignedRoles.first.color != null
                ? CircleAvatar(
                    radius: 6,
                    backgroundColor: Color(0xFF000000 | assignedRoles.first.color!),
                  )
                : null,
            label: Text(
              assignedRoles.isEmpty
                  ? strings.groupRoleNoneLabel
                  : assignedRoles.map((r) => r.name).join('、'),
            ),
            onPressed: canManageRoles ? onEditRoles : null,
          ),
        ],
      ),
      // タップすると相手のプロフィールカードを見られ、友達でなければそこから
      // 友達申請を送れる（chat_screen.dartの送信者アイコンタップと同じ導線）。
      onTap: () =>
          UserProfileCardDialog.show(context, currentUser: currentUser, user: user),
    );
  }
}
