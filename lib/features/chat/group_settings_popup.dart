import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/group_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/group_permissions.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_surface.dart';
import 'chat_panes.dart' show confirmDisableReadReceipts;
import 'conversation_profile_card_dialog.dart';
import 'group_delete_dialog.dart';
import 'group_invite_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';
import 'group_role_list_popup.dart';

/// [GroupSettingsPopup]をガラスUI対応のダイアログでラップして開く
/// （2026-09-02、サイドバーの歯車アイコン（`talks_tab.dart`）に加え、狭い
/// 画面のハンバーガーメニュー（`chat_panes.dart`の`_GroupMenuButton`）からも
/// 同じ開き方を再利用できるよう切り出した）。
Future<void> showGroupSettingsDialog(
  BuildContext context, {
  required AppUser currentUser,
  required Group group,
  required bool isGlass,
}) {
  return showDialog<void>(
    context: context,
    // 「自分のプロフィールカード」の項目は蔵が複数ある時だけ増える
    // （GroupSettingsPopup参照）ため、固定の高さ1つでは項目がある時に
    // 一覧の下端が僅かに入りきらなかった（2026-08-12修正、有無で高さを
    // 2種類使い分ける）。
    builder: (_) {
      final constrained = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: currentUser.profileCards.length > 1 ? 696 : 640,
        ),
        child: GroupSettingsPopup(currentUser: currentUser, group: group),
      );
      // ガラステーマはdialogThemeの背景を透明にしている（`GlassAlertDialog`
      // が自前でGlassSurfaceをラップする前提の設計）ため、素の`Dialog`の
      // ままだと背景が完全に透明になっていた（2026-08-30修正）。
      return isGlass
          ? Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: GlassSurface(
                variant: GlassVariant.floating,
                borderRadius: BorderRadius.circular(24),
                child: constrained,
              ),
            )
          : Dialog(child: constrained);
    },
  );
}

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
/// ただし狭い画面（`RoomTabBar`使用）は複数モードでもサイドバー自体を
/// 持たないため、[showGroupSettingsDialog]を`_GroupMenuButton`からも呼べる
/// ようにしている（2026-09-02、モバイルで複数寄合時に広場設定へ到達できない
/// 不具合の修正）。
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
    required bool isGlass,
    double maxWidth = 400,
    double maxHeight = 640,
  }) {
    final constrained = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: child,
    );
    return showDialog<void>(
      context: context,
      // ガラステーマはdialogThemeの背景を透明にしている（`GlassAlertDialog`
      // が自前でGlassSurfaceをラップする前提の設計）ため、素の`Dialog`の
      // ままだと背景が完全に透明になっていた（2026-08-30修正）。
      builder: (_) => isGlass
          ? Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: GlassSurface(
                variant: GlassVariant.floating,
                borderRadius: BorderRadius.circular(24),
                child: constrained,
              ),
            )
          : Dialog(child: constrained),
    );
  }

  /// 寄合機能（複数寄合）のオン/オフを切り替える（2026-09-14変更、以前の
  /// 3択「単一／複数／寄合機能なし」を1つのトグルに簡略化した。2026-09-15、
  /// オフにする前の確認ダイアログを廃止し、トグル操作で即座に反映される
  /// ようにした）。オフへの変更は寄合が1つだけの場合しか許可されない
  /// （`GroupRepository.setRoomsEnabled`が件数を検証し[StateError]を
  /// 投げる）が、UI側も寄合が複数ある間はトグル自体を無効化するため、
  /// 通常はここに到達する前に弾かれる（購読中の件数と実際の書き込み
  /// 時点の件数がずれる競合状態のみフォールバックとしてここで捕捉する）。
  Future<void> _toggleRoomsEnabled(
    BuildContext context,
    WidgetRef ref,
    String userId,
    bool enabled,
  ) async {
    try {
      await ref
          .read(groupRepositoryProvider)
          .setRoomsEnabled(
            groupId: group.groupId,
            enabled: enabled,
            requestedBy: userId,
          );
    } on StateError catch (e) {
      if (context.mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final userId = currentUser.userId;
    // ポップアップを開いたまま設定を切り替えても見た目がすぐ反映されるよう、
    // 呼び出し元から渡された一度きりのスナップショットではなく、ここで
    // `watchedGroupProvider`を直接watchする（2026-09-14修正。以前は
    // コンストラクタ引数`group`を使っており、寄合機能トグル操作時に
    // Firestoreへの書き込み自体は成功してもスイッチの見た目だけ更新
    // されなかった。`group_role_list_popup.dart`/`group_member_list_screen.dart`
    // と同じ既存パターンを踏襲）。
    final liveGroup =
        ref.watch(watchedGroupProvider(group.groupId)).value ?? group;
    final canManageRoles = hasGroupPermission(
      group: liveGroup,
      userId: userId,
      permission: GroupPermission.manageRoles,
    );
    final canCreateInvite = hasGroupPermission(
      group: liveGroup,
      userId: userId,
      permission: GroupPermission.createInvite,
    );
    final canManageReadReceipts = hasGroupPermission(
      group: liveGroup,
      userId: userId,
      permission: GroupPermission.manageReadReceipts,
    );
    final canManageRooms = hasGroupPermission(
      group: liveGroup,
      userId: userId,
      permission: GroupPermission.manageRooms,
    );
    final prefs =
        ref.watch(conversationPrefsProvider(userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[liveGroup.groupId]?.notificationsMuted ?? false;
    final readReceiptsEnabled = liveGroup.readReceiptsEnabled;

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
                  GroupProfileCardPopup(group: liveGroup),
                  isGlass: isGlass,
                ),
              ),
              if (currentUser.profileCards.length > 1)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(strings.conversationProfileCardMenuLabel),
                  onTap: () => ConversationProfileCardDialog.show(
                    context,
                    currentUserId: currentUser.userId,
                    conversationId: liveGroup.groupId,
                  ),
                ),
              StreamBuilder<List<GroupRole>>(
                stream: ref
                    .read(groupRepositoryProvider)
                    .watchRoles(liveGroup.groupId),
                builder: (context, snapshot) {
                  final roles = snapshot.data ?? const <GroupRole>[];
                  return ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: Text(strings.groupMenuMemberList),
                    onTap: () => _openSubDialog(
                      context,
                      GroupMemberListPopup(
                        currentUser: currentUser,
                        group: liveGroup,
                        roles: roles,
                      ),
                      isGlass: isGlass,
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
                        liveGroup.groupId,
                        liveGroup.profileCard,
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
                          group: liveGroup,
                        ),
                        isGlass: isGlass,
                      ),
              ),
              const Divider(),
              StreamBuilder<List<Room>>(
                stream: ref
                    .read(groupRepositoryProvider)
                    .watchRooms(groupId: liveGroup.groupId, userId: userId),
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? const <Room>[];
                  final locked = liveGroup.roomsEnabled && rooms.length > 1;
                  final colorScheme = Theme.of(context).colorScheme;
                  return SwitchListTile(
                    value: liveGroup.roomsEnabled,
                    title: Text(
                      strings.groupMenuEnableMultipleRooms,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: locked
                        ? Text(
                            strings.roomModeToggleLockedHint,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    onChanged: !canManageRooms || locked
                        ? null
                        : (value) =>
                              _toggleRoomsEnabled(context, ref, userId, value),
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
                      conversationId: liveGroup.groupId,
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
                              groupId: liveGroup.groupId,
                              enabled: value,
                              userId: userId,
                            );
                      },
              ),
              const Divider(),
              ListTile(
                title: DestructiveLabel(strings.groupDeleteMenuLabel),
                enabled: liveGroup.ownerId == userId,
                onTap: () => GroupDeleteDialog.show(
                  context,
                  groupId: liveGroup.groupId,
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
