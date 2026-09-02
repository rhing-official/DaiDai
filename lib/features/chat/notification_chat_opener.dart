import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import 'chat_panes.dart';

/// プッシュ通知タップ時、`dmId`/`groupId`（＋任意の`roomId`）だけから
/// 該当の語らい画面まで開くための解決役（2026-09-02追加）。
///
/// `app_router.dart`の既存の`/chat/dm`・`/chat/group`ルートは、TalksTab側で
/// 既に取得済みの`AppUser`・`DirectMessage`/`Group`オブジェクト一式を
/// `state.extra`で受け取る設計のため、通知タップ（cold start含む）のように
/// ID単体しか持たない場面では使えない。ここでは
/// [talks_tab.dart]の`_openDirectMessage`/`_openGroup`と同じ手順
/// （寄合一覧を取得し、`roomId`があればそれを・無ければ先頭の寄合を選ぶ）で
/// 必要なオブジェクトを解決してから[DmChatPane]/[GroupChatPane]を組み立てる。
class NotificationChatOpener extends ConsumerWidget {
  const NotificationChatOpener({
    required this.currentUser,
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    super.key,
  });

  final AppUser currentUser;
  final bool isDm;
  final String conversationId;

  /// 通知ペイロード由来のroomId（無効・未指定なら先頭の寄合にフォールバック）。
  final String? roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return isDm ? _buildDm(context, ref) : _buildGroup(context, ref);
  }

  Widget _buildDm(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: _resolveDm(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/');
          });
          return const SizedBox.shrink();
        }
        return DmChatPane(
          currentUser: currentUser,
          dm: resolved.dm,
          roomId: resolved.roomId,
          roomName: resolved.roomName,
          showRoomTabBar: true,
          onSwipeBack: () {
            final router = GoRouter.of(context);
            if (router.canPop()) router.pop();
          },
        );
      },
    );
  }

  Widget _buildGroup(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: _resolveGroup(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/');
          });
          return const SizedBox.shrink();
        }
        return GroupChatPane(
          currentUser: currentUser,
          group: resolved.group,
          roomId: resolved.roomId,
          roomName: resolved.roomName,
          showRoomTabBar: true,
          onSwipeBack: () {
            final router = GoRouter.of(context);
            if (router.canPop()) router.pop();
          },
        );
      },
    );
  }

  Future<({DirectMessage dm, String roomId, String roomName})?> _resolveDm(
    WidgetRef ref,
  ) async {
    final repository = ref.read(directMessageRepositoryProvider);
    final dm = await repository.getDirectMessage(conversationId);
    if (dm == null || !dm.participants.contains(currentUser.userId)) {
      return null;
    }
    final rooms = await repository
        .watchRooms(dmId: dm.dmId, userId: currentUser.userId)
        .first;
    final targetRoomId =
        rooms.firstWhereOrNull((r) => r.roomId == roomId)?.roomId ??
        (rooms.isNotEmpty ? rooms.first.roomId : dm.defaultRoomId);
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == targetRoomId)?.name ?? 'メイン';
    return (dm: dm, roomId: targetRoomId, roomName: roomName);
  }

  Future<({Group group, String roomId, String roomName})?> _resolveGroup(
    WidgetRef ref,
  ) async {
    final repository = ref.read(groupRepositoryProvider);
    final group = await repository.getGroup(conversationId);
    if (group == null || !group.memberIds.contains(currentUser.userId)) {
      return null;
    }
    final rooms = await repository
        .watchRooms(groupId: group.groupId, userId: currentUser.userId)
        .first;
    final targetRoomId =
        rooms.firstWhereOrNull((r) => r.roomId == roomId)?.roomId ??
        (rooms.isNotEmpty ? rooms.first.roomId : group.defaultRoomId);
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == targetRoomId)?.name ?? 'メイン';
    return (group: group, roomId: targetRoomId, roomName: roomName);
  }
}
