import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_join_request.dart';
import '../../models/group_role.dart';
import '../../providers/repository_providers.dart';
import 'user_profile_card_dialog.dart';

/// 広場のメンバー一覧（ポップアップの中身）。長・モデレーターには、招待リンクからの
/// 参加リクエストの承認・却下UIもあわせて表示する。メンバー本体を先に、
/// 招待中（承認待ち）は最下部にまとめて表示する。長・モデレーターには、
/// カスタムロールの付与UI（広場全体／この寄合のみの切り替え）もあわせて出す
/// （2026-07-28追加）。
class GroupMemberListPopup extends ConsumerStatefulWidget {
  const GroupMemberListPopup({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
    super.key,
  });

  final AppUser currentUser;
  final Group group;
  final String roomId;
  final String roomName;

  @override
  ConsumerState<GroupMemberListPopup> createState() => _GroupMemberListPopupState();
}

class _GroupMemberListPopupState extends ConsumerState<GroupMemberListPopup> {
  // false: 広場全体への付与を編集。true: 現在の寄合限定の付与を編集。
  bool _scopeIsRoom = false;

  /// 「解除」が選ばれたことを表す番人値。バリア外タップ等でダイアログが
  /// 閉じられた場合の`null`（＝何も変更しない）と区別するために使う
  /// （どちらもnullを返すと、誤タップで解除してしまうバグになるため）。
  static const _clearRoleSentinel = '__clear__';

  Future<void> _pickRole(
    BuildContext context,
    Strings strings,
    List<GroupRole> roles,
    String? currentRoleId,
    ValueChanged<String?> onPicked,
  ) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.groupRolePickerTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_clearRoleSentinel),
            child: Text(strings.groupRolePickerNone),
          ),
          for (final role in roles)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(role.roleId),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 8,
                    backgroundColor: Color(0xFF000000 | role.color),
                  ),
                  const SizedBox(width: 8),
                  Text(role.name),
                ],
              ),
            ),
        ],
      ),
    );
    // ダイアログをバリア外タップ等で閉じた場合（picked == null）は
    // 何も変更しない。
    if (picked == null || !context.mounted) return;
    onPicked(picked == _clearRoleSentinel ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final group = widget.group;
    final role = group.memberRoles[widget.currentUser.userId];
    final canApprove = role == 'owner' || role == 'moderator';
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
        if (canApprove)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(strings.groupRoleAssignmentScopeAll(vocab.plaza)),
                  selected: !_scopeIsRoom,
                  onSelected: (_) => setState(() => _scopeIsRoom = false),
                ),
                ChoiceChip(
                  label:
                      Text(strings.groupRoleAssignmentScopeRoom(widget.roomName)),
                  selected: _scopeIsRoom,
                  onSelected: (_) => setState(() => _scopeIsRoom = true),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Flexible(
          child: StreamBuilder<List<GroupRole>>(
            stream: groupRepository.watchRoles(group.groupId),
            builder: (context, rolesSnapshot) {
              final roles = rolesSnapshot.data ?? const <GroupRole>[];
              return StreamBuilder<List<Room>>(
                stream: groupRepository.watchRooms(group.groupId),
                builder: (context, roomsSnapshot) {
                  final currentRoom = (roomsSnapshot.data ?? const <Room>[])
                      .where((r) => r.roomId == widget.roomId)
                      .firstOrNull;
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _SectionHeader(strings.groupMemberListMembersSection),
                      FutureBuilder<List<AppUser>>(
                        future: ref
                            .read(userRepositoryProvider)
                            .getUsersByIds(group.memberIds),
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
                                  currentUser: widget.currentUser,
                                  user: member,
                                  role: group.memberRoles[member.userId] ?? 'member',
                                  vocab: vocab,
                                  strings: strings,
                                  customRoles: roles,
                                  assignedRoleId: _scopeIsRoom
                                      ? currentRoom?.roleAssignments[member.userId]
                                      : group.roleAssignments[member.userId],
                                  canManageRole: canApprove,
                                  onChangeRole: !canApprove
                                      ? null
                                      : () => _pickRole(
                                            context,
                                            strings,
                                            roles,
                                            _scopeIsRoom
                                                ? currentRoom
                                                    ?.roleAssignments[member.userId]
                                                : group.roleAssignments[
                                                    member.userId],
                                            (roleId) => _scopeIsRoom
                                                ? groupRepository.assignRoomRole(
                                                    groupId: group.groupId,
                                                    roomId: widget.roomId,
                                                    userId: member.userId,
                                                    roleId: roleId,
                                                  )
                                                : groupRepository.assignRole(
                                                    groupId: group.groupId,
                                                    userId: member.userId,
                                                    roleId: roleId,
                                                  ),
                                          ),
                                ),
                            ],
                          );
                        },
                      ),
                      if (canApprove) ...[
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
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
              );
            },
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
    required this.role,
    required this.vocab,
    required this.strings,
    required this.customRoles,
    required this.assignedRoleId,
    required this.canManageRole,
    required this.onChangeRole,
  });

  final AppUser currentUser;
  final AppUser user;
  final String role;
  final Vocabulary vocab;
  final Strings strings;

  /// このユーザーが選べるカスタムロールの一覧（見た目専用、2026-07-28追加）。
  final List<GroupRole> customRoles;

  /// 現在の付与範囲（広場全体／この寄合のみ）での付与ロールid。未付与ならnull。
  final String? assignedRoleId;

  /// 長・モデレーターのみtrue。falseの場合、カスタムロールチップは
  /// タップ不可の表示専用になる。
  final bool canManageRole;
  final VoidCallback? onChangeRole;

  // モデレーターという言葉自体は表示しない方針にしたため、モデレーターも
  // 通常のメンバーと同じラベルで表示する（権限自体は引き続き役割として持つ）。
  String get _roleLabel => switch (role) {
        'owner' => vocab.owner,
        _ => strings.groupRoleMember,
      };

  @override
  Widget build(BuildContext context) {
    final iconUrl = user.effectiveIcon?.url;
    final nickname = user.effectiveNickname?.text;
    final label = (nickname?.isNotEmpty ?? false) ? nickname! : '@${user.rhingId}';
    final assignedRole =
        customRoles.where((r) => r.roleId == assignedRoleId).firstOrNull;
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
          Chip(label: Text(_roleLabel)),
          const SizedBox(height: 4),
          ActionChip(
            avatar: assignedRole != null
                ? CircleAvatar(
                    radius: 6,
                    backgroundColor: Color(0xFF000000 | assignedRole.color),
                  )
                : null,
            label: Text(
              assignedRole?.name ?? strings.groupRoleNoneLabel,
              style: TextStyle(
                color: assignedRole != null
                    ? Color(0xFF000000 | assignedRole.color)
                    : null,
              ),
            ),
            onPressed: canManageRole ? onChangeRole : null,
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
