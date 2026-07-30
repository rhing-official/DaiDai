import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/group_permissions.dart';
import 'group_settings_popup.dart';
import 'room_list_pane.dart';

/// サイドバーの固定幅。`TalksTab`の広い画面レイアウトと同じ値を使う
/// （2026-07-29追加、以前はこの画面いっぱいにリストを広げていたが、
/// Discordを参考にあくまでサイドバーとして見えるよう幅を制限した）。
const _sidebarWidth = 220.0;

/// 一対の寄合一覧（狭い画面でのドリルダウン用フルスクリーン、`/chat/dm-rooms`）。
/// 寄合をタップすると`/chat/dm`へ選択した寄合を添えてpushする。
class DmRoomListScreen extends ConsumerWidget {
  const DmRoomListScreen({
    required this.currentUser,
    required this.dm,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('@${dm.otherRhingId(currentUser.userId)}')),
      body: StreamBuilder<List<DmRoom>>(
        stream: dmRepository.watchRooms(
          dmId: dm.dmId,
          userId: currentUser.userId,
        ),
        builder: (context, snapshot) {
          final rooms = snapshot.data ?? const <DmRoom>[];
          return Row(
            children: [
              SizedBox(
                width: _sidebarWidth,
                child: RoomListPane(
                  conversationName: '@${dm.otherRhingId(currentUser.userId)}',
                  rooms: [
                    for (final r in rooms) (roomId: r.roomId, name: r.name),
                  ],
                  selectedRoomId: null,
                  onSelectRoom: (room) => ref
                      .read(goRouterProvider)
                      .push(
                        '/chat/dm',
                        extra: DmChatArgs(
                          currentUser: currentUser,
                          dm: dm,
                          roomId: room.roomId,
                          roomName: room.name,
                        ),
                      ),
                  onCreateRoom: (name) =>
                      dmRepository.createRoom(dmId: dm.dmId, name: name),
                ),
              ),
              const VerticalDivider(width: 1),
              const Expanded(child: _EmptyRoomListPlaceholder()),
            ],
          );
        },
      ),
    );
  }
}

/// 広場の寄合一覧（狭い画面でのドリルダウン用フルスクリーン、
/// `/chat/group-rooms`）。寄合をタップすると`/chat/group`へ選択した
/// 寄合を添えてpushする。寄合の追加・削除は長・モデレーターのみ
/// （firestore.rulesで強制、ここではUI上の操作可否も合わせる）。
class GroupRoomListScreen extends ConsumerWidget {
  const GroupRoomListScreen({
    required this.currentUser,
    required this.group,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupRepository = ref.watch(groupRepositoryProvider);
    final canManageRooms = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageRooms,
    );
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: StreamBuilder<List<Room>>(
        stream: groupRepository.watchRooms(
          groupId: group.groupId,
          userId: currentUser.userId,
        ),
        builder: (context, snapshot) {
          final rooms = snapshot.data ?? const <Room>[];
          return Row(
            children: [
              SizedBox(
                width: _sidebarWidth,
                child: RoomListPane(
                  conversationName: group.name,
                  rooms: [
                    for (final r in rooms) (roomId: r.roomId, name: r.name),
                  ],
                  selectedRoomId: null,
                  onSelectRoom: (room) => ref
                      .read(goRouterProvider)
                      .push(
                        '/chat/group',
                        extra: GroupChatArgs(
                          currentUser: currentUser,
                          group: group,
                          roomId: room.roomId,
                          roomName: room.name,
                        ),
                      ),
                  onCreateRoom: canManageRooms
                      ? (name) => groupRepository.createRoom(
                          groupId: group.groupId,
                          name: name,
                        )
                      : null,
                  // 全体設定ポップアップ自体は全メンバーが開ける（中の各項目が
                  // 個別に権限ゲートされる、2026-07-29変更）。
                  onOpenGroupSettings: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 420,
                          maxHeight: 640,
                        ),
                        child: GroupSettingsPopup(
                          currentUser: currentUser,
                          group: group,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              const Expanded(child: _EmptyRoomListPlaceholder()),
            ],
          );
        },
      ),
    );
  }
}

/// サイドバー化した寄合一覧の右側に表示する余白エリア（2026-07-29追加）。
/// `TalksTab._EmptyDetailPlaceholder`と同じ見た目（会話未選択時の
/// プレースホルダー）を、この画面専用に複製している。
class _EmptyRoomListPlaceholder extends StatelessWidget {
  const _EmptyRoomListPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.forum_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
