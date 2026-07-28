import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
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
    final isOwnerOrModerator =
        group.memberRoles[currentUser.userId] == 'owner' ||
            group.memberRoles[currentUser.userId] == 'moderator';
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: RoomListPane(
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
        onCreateRoom: isOwnerOrModerator
            ? (name) => groupRepository.createRoom(groupId: group.groupId, name: name)
            : null,
        onDeleteRoom: isOwnerOrModerator
            ? (roomId) => groupRepository.deleteRoom(
                  groupId: group.groupId,
                  roomId: roomId,
                  requestedBy: currentUser.userId,
                )
            : null,
      ),
    );
  }
}
