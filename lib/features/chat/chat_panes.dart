import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/block_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/group_call_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../router/app_router.dart';
import 'chat_screen.dart';
import 'group_invite_dialog.dart';
import 'group_leave_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';

enum _GroupMenuAction {
  profileCard,
  memberList,
  createInvite,
  toggleMute,
  toggleReadReceipts,
  leave,
}
enum _DmMenuAction { toggleMute, toggleBlock, toggleReadReceipts }

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
    final strings = ref.watch(appStringsProvider);
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final otherUserId = dm.otherUserId(currentUser.userId);
    final fallbackTitle = '@${dm.otherRhingId(currentUser.userId)}';
    final otherUser = ref.watch(watchedUserProvider(otherUserId));
    final nickname = otherUser.maybeWhen(
      data: (user) => user?.activeNickname?.text,
      orElse: () => null,
    );
    final blockedIds =
        ref.watch(blockedUserIdsProvider(currentUser.userId)).value ??
            const {};
    final isBlocked = blockedIds.contains(otherUserId);
    final prefs = ref
            .watch(conversationPrefsProvider(currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final readReceiptsEnabled = prefs[dm.dmId]?.readReceiptsEnabled ?? true;
    return ChatScreen(
      key: ValueKey('dm-${dm.dmId}'),
      title: (nickname?.isNotEmpty ?? false) ? nickname! : fallbackTitle,
      currentUserId: currentUser.userId,
      isDm: true,
      // ブロック中は相手からのメッセージを表示しない（自分が送った過去分は
      // 引き続き見える）。サーバー側の送信拒否ではなく、クライアント側の
      // 表示抑制で実現する（`BlockRepository`のコメント参照）。
      messagesStream: dmRepository.watchMessages(dm.dmId).map(
            (messages) => isBlocked
                ? messages.where((m) => m.senderId != otherUserId).toList()
                : messages,
          ),
      onSend: (content, {silent = false}) async {
        if (isBlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.conversationBlockedCannotSend)),
          );
          return;
        }
        await dmRepository.sendTextMessage(
          dmId: dm.dmId,
          senderId: currentUser.userId,
          senderRhingId: currentUser.rhingId,
          content: content,
          silent: silent,
        );
      },
      onCallPressed: onCallPressed,
      onVideoCallPressed: onVideoCallPressed,
      readReceiptsEnabled: readReceiptsEnabled,
      onMarkRead: (messageIds) => dmRepository.markMessagesRead(
        dmId: dm.dmId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      extraActions: [
        _DmMenuButton(
          currentUser: currentUser,
          dm: dm,
          otherUserId: otherUserId,
          isBlocked: isBlocked,
        ),
      ],
    );
  }
}

/// 一対の「通知オフ・ブロック」をまとめたハンバーガーメニュー（2026-07-25追加）。
/// 見た目は広場のハンバーガーメニュー（[_GroupMenuButton]）から転用し、
/// ボタン真下に角丸で開く。一対にはメンバー一覧・プロフィールカードのような
/// サブ画面が無いため、[_GroupMenuButton]と違い単純な[PopupMenuButton]のみで足りる。
class _DmMenuButton extends ConsumerWidget {
  const _DmMenuButton({
    required this.currentUser,
    required this.dm,
    required this.otherUserId,
    required this.isBlocked,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final String otherUserId;
  final bool isBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final prefs = ref
            .watch(conversationPrefsProvider(currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[dm.dmId]?.notificationsMuted ?? false;
    final readReceiptsEnabled = prefs[dm.dmId]?.readReceiptsEnabled ?? true;

    return PopupMenuButton<_DmMenuAction>(
      icon: const Icon(Icons.menu),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) {
        switch (action) {
          case _DmMenuAction.toggleMute:
            ref.read(conversationPrefsRepositoryProvider).setNotificationsMuted(
                  userId: currentUser.userId,
                  conversationId: dm.dmId,
                  muted: !muted,
                );
          case _DmMenuAction.toggleBlock:
            final repository = ref.read(blockRepositoryProvider);
            if (isBlocked) {
              repository.unblock(
                userId: currentUser.userId,
                targetUserId: otherUserId,
              );
            } else {
              repository.block(
                userId: currentUser.userId,
                targetUserId: otherUserId,
              );
            }
          case _DmMenuAction.toggleReadReceipts:
            ref.read(conversationPrefsRepositoryProvider).setReadReceiptsEnabled(
                  userId: currentUser.userId,
                  conversationId: dm.dmId,
                  enabled: !readReceiptsEnabled,
                );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _DmMenuAction.toggleMute,
          child: Text(muted ? strings.conversationUnmute : strings.conversationMute),
        ),
        PopupMenuItem(
          value: _DmMenuAction.toggleBlock,
          child: Text(
            isBlocked ? strings.conversationUnblock : strings.conversationBlock,
          ),
        ),
        PopupMenuItem(
          value: _DmMenuAction.toggleReadReceipts,
          child: Text(
            readReceiptsEnabled
                ? strings.conversationReadReceiptsDisable
                : strings.conversationReadReceiptsEnable,
          ),
        ),
      ],
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
    final prefs = ref
            .watch(conversationPrefsProvider(currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final readReceiptsEnabled =
        prefs[group.groupId]?.readReceiptsEnabled ?? true;
    return ChatScreen(
      key: ValueKey('group-${group.groupId}'),
      title: group.name,
      currentUserId: currentUser.userId,
      isDm: false,
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
      readReceiptsEnabled: readReceiptsEnabled,
      onMarkRead: (messageIds) => groupRepository.markRoomMessagesRead(
        groupId: group.groupId,
        roomId: group.defaultRoomId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      extraActions: [
        _GroupMenuButton(currentUser: currentUser, group: group),
      ],
    );
  }
}

/// ハンバーガーメニュー・メンバー一覧・プロフィールカードいずれのポップアップも
/// 使う共通の見た目（角丸のMaterialカード）。
class _PopupCard extends StatelessWidget {
  const _PopupCard({required this.child, required this.constraints});

  final Widget child;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: constraints, child: child),
    );
  }
}

/// 広場の「プロフィールカード・メンバー一覧・招待リンク作成・退会」を
/// まとめたハンバーガーメニュー（2026-07-24追加、広場のカスタマイズ機能）。
/// メニュー自体はボタンの真下に開く（`PopupMenuPosition.under`）。
/// メンバー一覧・プロフィールカードは全画面遷移ではなく、それぞれボタンの
/// 左隣・画面中央に角丸のポップアップとして開く（2026-07-25変更）。
class _GroupMenuButton extends ConsumerStatefulWidget {
  const _GroupMenuButton({required this.currentUser, required this.group});

  final AppUser currentUser;
  final Group group;

  @override
  ConsumerState<_GroupMenuButton> createState() => _GroupMenuButtonState();
}

class _GroupMenuButtonState extends ConsumerState<_GroupMenuButton> {
  final _buttonKey = GlobalKey();

  Rect _buttonRect() {
    final box = _buttonKey.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // メンバー一覧ポップアップを、ハンバーガーメニューのボタンの左隣（右端を
  // ボタンの左端に合わせる位置）に表示する。画面外にはみ出す場合は画面内に収める。
  Future<void> _showMemberListPopup() {
    final buttonRect = _buttonRect();
    const width = 340.0;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenSize = MediaQuery.sizeOf(context);
        final left =
            (buttonRect.left - width).clamp(8.0, screenSize.width - width - 8.0);
        final top = buttonRect.top;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: _PopupCard(
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: screenSize.height - top - 24,
                ),
                child: GroupMemberListPopup(
                  currentUser: widget.currentUser,
                  group: widget.group,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProfileCardPopup() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: _PopupCard(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
            child: GroupProfileCardPopup(group: widget.group),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isOwner =
        widget.group.memberRoles[widget.currentUser.userId] == 'owner';
    final prefs = ref
            .watch(conversationPrefsProvider(widget.currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[widget.group.groupId]?.notificationsMuted ?? false;
    final readReceiptsEnabled =
        prefs[widget.group.groupId]?.readReceiptsEnabled ?? true;

    return PopupMenuButton<_GroupMenuAction>(
      key: _buttonKey,
      icon: const Icon(Icons.menu),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) {
        switch (action) {
          case _GroupMenuAction.profileCard:
            _showProfileCardPopup();
          case _GroupMenuAction.memberList:
            _showMemberListPopup();
          case _GroupMenuAction.createInvite:
            GroupInviteDialog.show(context, widget.group.groupId);
          case _GroupMenuAction.toggleMute:
            ref.read(conversationPrefsRepositoryProvider).setNotificationsMuted(
                  userId: widget.currentUser.userId,
                  conversationId: widget.group.groupId,
                  muted: !muted,
                );
          case _GroupMenuAction.toggleReadReceipts:
            ref.read(conversationPrefsRepositoryProvider).setReadReceiptsEnabled(
                  userId: widget.currentUser.userId,
                  conversationId: widget.group.groupId,
                  enabled: !readReceiptsEnabled,
                );
          case _GroupMenuAction.leave:
            GroupLeaveDialog.show(
              context,
              groupId: widget.group.groupId,
              userId: widget.currentUser.userId,
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
          value: _GroupMenuAction.toggleMute,
          child: Text(muted ? strings.conversationUnmute : strings.conversationMute),
        ),
        PopupMenuItem(
          value: _GroupMenuAction.toggleReadReceipts,
          child: Text(
            readReceiptsEnabled
                ? strings.conversationReadReceiptsDisable
                : strings.conversationReadReceiptsEnable,
          ),
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
