import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/group_permissions.dart';
import 'group_role_list_popup.dart';
import 'room_list_pane.dart';

/// 一対の寄合一覧（狭い画面でのドリルダウン用フルスクリーン、`/chat/dm-rooms`）。
/// 寄合をタップすると`/chat/dm`へ選択した寄合を添えてpushする。
class DmRoomListScreen extends ConsumerWidget {
  const DmRoomListScreen({required this.currentUser, required this.dm, super.key});

  final AppUser currentUser;
  final DirectMessage dm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('@${dm.otherRhingId(currentUser.userId)}')),
      body: RoomListPane(
        conversationName: '@${dm.otherRhingId(currentUser.userId)}',
        roomsStream: dmRepository.watchRooms(dm.dmId).map(
              (rooms) =>
                  [for (final r in rooms) (roomId: r.roomId, name: r.name)],
            ),
        selectedRoomId: null,
        onSelectRoom: (room) => ref.read(goRouterProvider).push(
              '/chat/dm',
              extra: DmChatArgs(
                currentUser: currentUser,
                dm: dm,
                roomId: room.roomId,
                roomName: room.name,
              ),
            ),
        onCreateRoom: (name) => dmRepository.createRoom(dmId: dm.dmId, name: name),
        onDeleteRoom: (roomId) => dmRepository.deleteRoom(
          dmId: dm.dmId,
          roomId: roomId,
          requestedBy: currentUser.userId,
        ),
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
    final canManageRoles = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageRoles,
    );
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: RoomListPane(
        conversationName: group.name,
        roomsStream: groupRepository.watchRooms(group.groupId).map(
              (rooms) =>
                  [for (final r in rooms) (roomId: r.roomId, name: r.name)],
            ),
        selectedRoomId: null,
        onSelectRoom: (room) => ref.read(goRouterProvider).push(
              '/chat/group',
              extra: GroupChatArgs(
                currentUser: currentUser,
                group: group,
                roomId: room.roomId,
                roomName: room.name,
              ),
            ),
        onCreateRoom: canManageRooms
            ? (name) => groupRepository.createRoom(groupId: group.groupId, name: name)
            : null,
        onDeleteRoom: canManageRooms
            ? (roomId) => groupRepository.deleteRoom(
                  groupId: group.groupId,
                  roomId: roomId,
                  requestedBy: currentUser.userId,
                )
            : null,
        onOpenGroupSettings: canManageRoles
            ? () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
                      child: GroupRoleListPopup(group: group),
                    ),
                  ),
                )
            : null,
      ),
    );
  }
}
