import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/group_call_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../router/app_router.dart';
import 'chat_screen.dart';
import 'group_invite_dialog.dart';
import 'group_leave_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';
import 'plaza_detail_dialog.dart';

enum _GroupMenuAction { profileCard, memberList, createInvite, leave }

/// 一対（DM）のChatScreenを組み立てる。相手のアクティブなニックネームを
/// タイトルに反映するためConsumer化している。go_routerのフルスクリーン遷移と、
/// TalksTabの分割ビュー（一覧の右隣に埋め込み表示）の両方から使う共通部品。
class DmChatPane extends ConsumerWidget {
  const DmChatPane({
    required this.currentUser,
    required this.dm,
    this.onCallPressed,
    this.onVideoCallPressed,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final VoidCallback? onCallPressed;
  final VoidCallback? onVideoCallPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final otherUserId = dm.otherUserId(currentUser.userId);
    final fallbackTitle = '@${dm.otherRhingId(currentUser.userId)}';
    final otherUser = ref.watch(watchedUserProvider(otherUserId));
    final nickname = otherUser.maybeWhen(
      data: (user) => user?.activeNickname?.text,
      orElse: () => null,
    );
    return ChatScreen(
      key: ValueKey('dm-${dm.dmId}'),
      title: (nickname?.isNotEmpty ?? false) ? nickname! : fallbackTitle,
      currentUserId: currentUser.userId,
      messagesStream: dmRepository.watchMessages(dm.dmId),
      onSend: (content, {silent = false}) => dmRepository.sendTextMessage(
        dmId: dm.dmId,
        senderId: currentUser.userId,
        senderRhingId: currentUser.rhingId,
        content: content,
        silent: silent,
      ),
      onCallPressed: onCallPressed,
      onVideoCallPressed: onVideoCallPressed,
    );
  }
}

/// 広場（グループ）のChatScreenを組み立てる。DmChatPaneと同じ理由で共通部品化。
class GroupChatPane extends ConsumerWidget {
  const GroupChatPane({required this.currentUser, required this.group, super.key});

  final AppUser currentUser;
  final Group group;

  Future<void> _handleCallPressed(
    BuildContext context,
    WidgetRef ref, {
    required bool isVideo,
  }) async {
    final groupCallRepository = ref.read(groupCallRepositoryProvider);
    final activeCall = ref.read(activeGroupCallProvider(group.groupId)).value;

    if (activeCall != null) {
      final participants =
          await groupCallRepository.watchParticipants(activeCall.groupCallId).first;
      if (participants.length >= activeCall.maxParticipants) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'この通話は満員です（上限${activeCall.maxParticipants}人）',
              ),
            ),
          );
        }
        return;
      }
      if (!context.mounted) return;
      ref.read(goRouterProvider).push(
        '/group-call',
        extra: GroupCallArgs(
          groupCallId: activeCall.groupCallId,
          currentUser: currentUser,
          isVideo: activeCall.isVideo,
        ),
      );
      return;
    }

    final call = await groupCallRepository.createGroupCall(
      group: group,
      initiator: currentUser,
      isVideo: isVideo,
    );
    if (!context.mounted) return;
    ref.read(goRouterProvider).push(
      '/group-call',
      extra: GroupCallArgs(
        groupCallId: call.groupCallId,
        currentUser: currentUser,
        isVideo: call.isVideo,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupRepository = ref.watch(groupRepositoryProvider);
    // 通話ボタン押下時に「新規開始」か「参加」かを判定するため、進行中の通話を
    // 常時購読しておく（_handleCallPressedはref.readでキャッシュ値を使う）。
    ref.watch(activeGroupCallProvider(group.groupId));
    return ChatScreen(
      key: ValueKey('group-${group.groupId}'),
      title: group.name,
      currentUserId: currentUser.userId,
      showSenderAvatar: true,
      messagesStream: groupRepository.watchRoomMessages(
        group.groupId,
        group.defaultRoomId,
      ),
      onSend: (content, {silent = false}) => groupRepository.sendRoomMessage(
        groupId: group.groupId,
        roomId: group.defaultRoomId,
        senderId: currentUser.userId,
        senderRhingId: currentUser.rhingId,
        content: content,
        silent: silent,
      ),
      onCallPressed: () => _handleCallPressed(context, ref, isVideo: false),
      onVideoCallPressed: () => _handleCallPressed(context, ref, isVideo: true),
      extraActions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => PlazaDetailDialog.show(context, group),
        ),
        _GroupMenuButton(currentUser: currentUser, group: group),
      ],
    );
  }
}

/// 広場の「プロフィールカード・メンバー一覧・招待リンク作成・退会」を
/// まとめたハンバーガーメニュー（2026-07-24追加、広場のカスタマイズ機能）。
class _GroupMenuButton extends ConsumerWidget {
  const _GroupMenuButton({required this.currentUser, required this.group});

  final AppUser currentUser;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isOwner = group.memberRoles[currentUser.userId] == 'owner';

    return PopupMenuButton<_GroupMenuAction>(
      icon: const Icon(Icons.menu),
      onSelected: (action) {
        switch (action) {
          case _GroupMenuAction.profileCard:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupProfileCardScreen(group: group),
              ),
            );
          case _GroupMenuAction.memberList:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupMemberListScreen(
                  currentUser: currentUser,
                  group: group,
                ),
              ),
            );
          case _GroupMenuAction.createInvite:
            GroupInviteDialog.show(context, group.groupId);
          case _GroupMenuAction.leave:
            GroupLeaveDialog.show(
              context,
              groupId: group.groupId,
              userId: currentUser.userId,
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _GroupMenuAction.profileCard,
          child: Text(strings.groupMenuProfileCard),
        ),
        PopupMenuItem(
          value: _GroupMenuAction.memberList,
          child: Text(strings.groupMenuMemberList),
        ),
        PopupMenuItem(
          value: _GroupMenuAction.createInvite,
          child: Text(strings.groupMenuCreateInvite),
        ),
        PopupMenuItem(
          value: _GroupMenuAction.leave,
          enabled: !isOwner,
          child: Text(strings.groupMenuLeave),
        ),
      ],
    );
  }
}
