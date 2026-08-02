import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/group_permissions.dart';
import 'chat_panes.dart' show confirmDisableReadReceipts;
import 'conversation_profile_card_dialog.dart';
import 'group_delete_dialog.dart';
import 'group_invite_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';
import 'group_role_list_popup.dart';

/// 広場全体の設定をまとめたポップアップ（2026-07-29追加）。サイドバー
/// （`RoomListPane`）ヘッダーの歯車アイコンから開く。以前は寄合の
/// ハンバーガーメニューに置かれていたプロフィールカード・メンバー一覧・
/// 招待リンク作成をここへ移設し、通知オフ・既読機能のデフォルト値も
/// ここで設定する。寄合ごとに「この寄合独自の設定」（`_GroupMenuButton`参照）
/// をオンにすると、ここでの値より優先してその寄合だけ個別設定できる。
///
/// 単一モード（`Group.roomsEnabled == false`）の広場はサイドバー自体が
/// 無くこのポップアップを開けないため、例外的に全ての設定を寄合の
/// ハンバーガーメニューに残している（`_GroupMenuButton`のroomsEnabled分岐）。
class GroupSettingsPopup extends ConsumerWidget {
  const GroupSettingsPopup({
    required this.currentUser,
    required this.group,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  Future<void> _openSubDialog(
    BuildContext context,
    Widget child, {
    double maxWidth = 400,
    double maxHeight = 640,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: child,
        ),
      ),
    );
  }

  Future<void> _confirmDisableMultipleRooms(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    String userId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.groupSettingsDisableMultipleRoomsConfirmTitle),
        content: Text(strings.groupSettingsDisableMultipleRoomsConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.groupSettingsDisableMultipleRoomsConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(groupRepositoryProvider)
          .setRoomsEnabled(
            groupId: group.groupId,
            enabled: false,
            requestedBy: userId,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final userId = currentUser.userId;
    final canManageRoles = hasGroupPermission(
      group: group,
      userId: userId,
      permission: GroupPermission.manageRoles,
    );
    final canCreateInvite = hasGroupPermission(
      group: group,
      userId: userId,
      permission: GroupPermission.createInvite,
    );
    final canManageReadReceipts = hasGroupPermission(
      group: group,
      userId: userId,
      permission: GroupPermission.manageReadReceipts,
    );
    final canManageRooms = hasGroupPermission(
      group: group,
      userId: userId,
      permission: GroupPermission.manageRooms,
    );
    final prefs =
        ref.watch(conversationPrefsProvider(userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[group.groupId]?.notificationsMuted ?? false;
    final readReceiptsEnabled = group.readReceiptsEnabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.groupSettingsTooltip,
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
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(strings.groupMenuProfileCard),
                onTap: () => _openSubDialog(
                  context,
                  GroupProfileCardPopup(group: group),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(strings.conversationProfileCardMenuLabel),
                onTap: () => ConversationProfileCardDialog.show(
                  context,
                  currentUserId: currentUser.userId,
                  conversationId: group.groupId,
                ),
              ),
              StreamBuilder<List<GroupRole>>(
                stream: ref
                    .read(groupRepositoryProvider)
                    .watchRoles(group.groupId),
                builder: (context, snapshot) {
                  final roles = snapshot.data ?? const <GroupRole>[];
                  return ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: Text(strings.groupMenuMemberList),
                    onTap: () => _openSubDialog(
                      context,
                      GroupMemberListPopup(
                        currentUser: currentUser,
                        group: group,
                        roles: roles,
                      ),
                      maxWidth: 340,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(strings.groupMenuCreateInvite),
                enabled: canCreateInvite,
                onTap: !canCreateInvite
                    ? null
                    : () => GroupInviteDialog.show(
                        context,
                        group.groupId,
                        group.profileCard,
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(strings.groupMenuManageRoles),
                enabled: canManageRoles,
                onTap: !canManageRoles
                    ? null
                    : () => _openSubDialog(
                        context,
                        GroupRoleListPopup(
                          currentUser: currentUser,
                          group: group,
                        ),
                      ),
              ),
              const Divider(),
              StreamBuilder<List<Room>>(
                stream: ref
                    .read(groupRepositoryProvider)
                    .watchRooms(groupId: group.groupId, userId: userId),
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? const <Room>[];
                  final canDisable = canManageRooms && rooms.length <= 1;
                  return ListTile(
                    leading: const Icon(Icons.merge_type),
                    title: Text(strings.groupSettingsDisableMultipleRoomsLabel),
                    subtitle: Text(
                      rooms.length > 1
                          ? strings.groupSettingsDisableMultipleRoomsBlockedHint
                          : strings.groupSettingsDisableMultipleRoomsHint,
                    ),
                    enabled: canManageRooms,
                    onTap: !canDisable
                        ? null
                        : () => _confirmDisableMultipleRooms(
                            context,
                            ref,
                            strings,
                            userId,
                          ),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                value: muted,
                title: Text(strings.groupSettingsDefaultMuteLabel),
                subtitle: Text(strings.groupSettingsDefaultMuteHint),
                onChanged: (value) => ref
                    .read(conversationPrefsRepositoryProvider)
                    .setNotificationsMuted(
                      userId: userId,
                      conversationId: group.groupId,
                      muted: value,
                    ),
              ),
              SwitchListTile(
                value: readReceiptsEnabled,
                title: Text(strings.groupSettingsDefaultReadReceiptsLabel),
                subtitle: Text(strings.groupSettingsDefaultReadReceiptsHint),
                onChanged: !canManageReadReceipts
                    ? null
                    : (value) async {
                        if (!value) {
                          final confirmed = await confirmDisableReadReceipts(
                            context,
                            strings,
                          );
                          if (!confirmed) return;
                        }
                        ref
                            .read(groupRepositoryProvider)
                            .setReadReceiptsEnabled(
                              groupId: group.groupId,
                              enabled: value,
                              userId: userId,
                            );
                      },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  strings.groupDeleteMenuLabel,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                enabled: group.ownerId == userId,
                onTap: () => GroupDeleteDialog.show(
                  context,
                  groupId: group.groupId,
                  userId: userId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
