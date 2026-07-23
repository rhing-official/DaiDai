import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import 'chat_screen.dart';

/// 一対（DM）のChatScreenを組み立てる。相手のアクティブなニックネームを
/// タイトルに反映するためConsumer化している。go_routerのフルスクリーン遷移と、
/// TalksTabの分割ビュー（一覧の右隣に埋め込み表示）の両方から使う共通部品。
class DmChatPane extends ConsumerWidget {
  const DmChatPane({
    required this.currentUser,
    required this.dm,
    this.onCallPressed,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final VoidCallback? onCallPressed;

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
    );
  }
}

/// 広場（グループ）のChatScreenを組み立てる。DmChatPaneと同じ理由で共通部品化。
class GroupChatPane extends ConsumerWidget {
  const GroupChatPane({required this.currentUser, required this.group, super.key});

  final AppUser currentUser;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupRepository = ref.watch(groupRepositoryProvider);
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
    );
  }
}
