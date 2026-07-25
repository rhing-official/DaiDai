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
          value: _GroupMenuAction.leave,
          enabled: !isOwner,
          child: Text(strings.groupMenuLeave),
        ),
      ],
    );
  }
}
