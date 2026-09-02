import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_join_request.dart';
import '../../models/group_role.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/group_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/group_permissions.dart';
import '../../widgets/glass/glass_dialog.dart';
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
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final title = Text(strings.groupRolePickerTitle);
          final content = SingleChildScrollView(
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
          );
          final actions = [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.save),
            ),
          ];
          return isGlass
              ? GlassAlertDialog(
                  title: title,
                  content: content,
                  actions: actions,
                )
              : AlertDialog(title: title, content: content, actions: actions);
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
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.groupTransferOwnershipConfirmTitle);
        final content = Text(strings.groupTransferOwnershipConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.groupTransferOwnershipConfirmButton),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed == true) {
      await ref
          .read(groupRepositoryProvider)
          .transferOwnership(groupId: group.groupId, newOwnerId: member.userId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    // groupはこのポップアップが開かれた時点のスナップショットで、開いたまま
    // 長の譲渡・ロール変更等を行っても更新されない別Navigatorルートのため、
    // ライブな値を別途購読する（group_role_list_popup.dartのliveGroupと同じ理由）。
    final liveGroup =
        ref.watch(watchedGroupProvider(group.groupId)).value ?? group;
    final isOwner = liveGroup.ownerId == currentUser.userId;
    final canManageRoles = hasGroupPermission(
      group: liveGroup,
      userId: currentUser.userId,
      permission: GroupPermission.manageRoles,
    );
    final canManageJoinRequests = hasGroupPermission(
      group: liveGroup,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
                future: ref
                    .read(userRepositoryProvider)
                    .getUsersByIds(liveGroup.memberIds),
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
                          groupId: liveGroup.groupId,
                          isOwner: member.userId == liveGroup.ownerId,
                          strings: strings,
                          customRoles: roles,
                          assignedRoleIds:
                              liveGroup.roleAssignments[member.userId] ??
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
                                    ...?liveGroup.roleAssignments[member
                                        .userId],
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
                          _JoinRequestTile(
                            request: request,
                            strings: strings,
                            respondedBy: currentUser.userId,
                          ),
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
  const _JoinRequestTile({
    required this.request,
    required this.strings,
    required this.respondedBy,
  });

  final GroupJoinRequest request;
  final Strings strings;
  final String respondedBy;

  // 以前はawaitもエラーハンドリングも無い投げっぱなしで、失敗しても
  // ボタンの見た目だけが反応して何も起きていないように見えた（承認・却下が
  // 実は失敗していても気付けなかった）。エラー時は画面に表示する。
  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    bool accept,
  ) async {
    try {
      await ref
          .read(groupRepositoryProvider)
          .respondToJoinRequest(
            request: request,
            accept: accept,
            respondedBy: respondedBy,
          );
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: 'エラーが発生しました: $e');
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
    required this.groupId,
    required this.isOwner,
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

  /// 会話ごとに使うプロフィールカード（2026-07-29追加）を反映するための
  /// 広場id。
  final String groupId;

  /// このユーザーが長（[Group.ownerId]）かどうか。
  final bool isOwner;
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
    final iconUrl = user.effectiveIconFor(groupId)?.url;
    final nickname = user.effectiveNicknameFor(groupId)?.text;
    final label = (nickname?.isNotEmpty ?? false)
        ? nickname!
        : '@${user.rhingId}';
    final assignedRoles = customRoles
        .where((r) => assignedRoleIds.contains(r.roleId))
        .toList();
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        child: iconUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(label),
      // ロールチップをtrailingに縦積みすると、ListTileの既定の高さ
      // （1行分・56dp程度）に収まらずBOTTOM OVERFLOWが発生していたため、
      // subtitle（2行目扱いでListTileの高さが自動的に広がる）に移動した。
      subtitle: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: assignedRoles.isNotEmpty && assignedRoles.first.color != null
              ? CircleAvatar(
                  radius: 6,
                  backgroundColor: Color(
                    0xFF000000 | assignedRoles.first.color!,
                  ),
                )
              : null,
          label: Text(
            assignedRoles.isEmpty
                ? strings.groupRoleNoneLabel
                : assignedRoles.map((r) => r.name).join('、'),
          ),
          onPressed: canManageRoles ? onEditRoles : null,
        ),
      ),
      trailing: isOwner
          ? const Icon(Icons.workspace_premium, color: Colors.amber)
          : null,
      // タップすると相手のプロフィールカードを見られ、友達でなければそこから
      // 友達申請を送れる（chat_screen.dartの送信者アイコンタップと同じ導線）。
      // 長の譲渡も、以前はこの一覧に直接アイコンボタンを置いていたが誤操作の
      // リスクが高いため、プロフィールカード側の操作に統合した（2026-07-29）。
      onTap: () => UserProfileCardDialog.show(
        context,
        currentUser: currentUser,
        user: user,
        conversationId: groupId,
        canTransferOwnership: canTransferOwnership,
        onTransferOwnership: onTransferOwnership,
      ),
    );
  }
}
