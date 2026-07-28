import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/block_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/group_repository.dart';
import '../../router/app_router.dart';
import 'chat_screen.dart';
import 'group_invite_dialog.dart';
import 'group_leave_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';
import 'group_role_list_popup.dart';
import 'severance_dialog.dart';
import 'user_profile_card_dialog.dart';

enum _GroupMenuAction {
  profileCard,
  memberList,
  createInvite,
  manageRoles,
  toggleMute,
  toggleReadReceipts,
  leave,
}
enum _DmMenuAction {
  toggleMute,
  toggleBlock,
  toggleReadReceipts,
  proposeSeverance,
  deleteConversation,
}

/// 既読機能をオフにする方向の操作（広場: 長が直接オフにする／DM: オフを
/// 提案する・オフの提案を承認する）から共通で呼ぶ確認ダイアログ。
/// `chat_screen.dart`の`_confirmUnsend`と同じ、キャンセル/エラー色ボタンの形。
Future<bool> _confirmDisableReadReceipts(
  BuildContext context,
  Strings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.conversationReadReceiptsDisableConfirmTitle),
      content: Text(strings.conversationReadReceiptsDisableConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.conversationReadReceiptsDisableConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 一対の削除確認ダイアログ。`chat_screen.dart`の`_confirmDeleteConversation`
/// （アカウント削除通知メッセージの「はい」ボタンから呼ばれるもの）と同じ
/// 文言・見た目を使う（相手のアカウント削除通知に「いいえ」と答えた後、または
/// 未応答のまま、ハンバーガーメニューからいつでも削除できるようにする経路）。
Future<bool> _confirmDeleteDm(BuildContext context, Strings strings) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.chatAccountDeletedConfirmTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.chatAccountDeletedConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 一対（DM）のChatScreenを組み立てる。相手のアクティブなニックネームを
/// タイトルに反映するためConsumer化している。go_routerのフルスクリーン遷移と、
/// TalksTabの分割ビュー（一覧の右隣に埋め込み表示）の両方から使う共通部品。
class DmChatPane extends ConsumerWidget {
  const DmChatPane({
    required this.currentUser,
    required this.dm,
    required this.roomId,
    required this.roomName,
    this.onCallPressed,
    this.onVideoCallPressed,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;

  /// 現在表示中の寄合。呼び出し側（TalksTab分割表示、または狭画面の
  /// 寄合一覧画面）が選択状態を管理し、渡す。
  final String roomId;
  final String roomName;

  final VoidCallback? onCallPressed;
  final VoidCallback? onVideoCallPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final otherUserId = dm.otherUserId(currentUser.userId);
    final blockedIds =
        ref.watch(blockedUserIdsProvider(currentUser.userId)).value ??
            const {};
    final isBlocked = blockedIds.contains(otherUserId);
    return ChatScreen(
      key: ValueKey('dm-${dm.dmId}-$roomId'),
      title: roomName,
      currentUserId: currentUser.userId,
      isDm: true,
      // ブロック中は相手からのメッセージを表示しない（自分が送った過去分は
      // 引き続き見える）。サーバー側の送信拒否ではなく、クライアント側の
      // 表示抑制で実現する（`BlockRepository`のコメント参照）。
      // hiddenForに自分のuserIdが含まれるメッセージ（範囲選択削除で自分が
      // 削除したもの）も、相手には見えたままここでは表示しないだけにする。
      messagesStream: dmRepository.watchMessages(dm.dmId, roomId).map(
            (messages) => messages
                .where((m) => !m.hiddenFor.contains(currentUser.userId))
                .where((m) => !isBlocked || m.senderId != otherUserId)
                .toList(),
          ),
      onSend: (content, {silent = false, replyTo}) async {
        if (isBlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.conversationBlockedCannotSend)),
          );
          return;
        }
        await dmRepository.sendTextMessage(
          dmId: dm.dmId,
          roomId: roomId,
          senderId: currentUser.userId,
          senderRhingId: currentUser.rhingId,
          content: content,
          silent: silent,
          replyTo: replyTo,
        );
      },
      onCallPressed: onCallPressed,
      onVideoCallPressed: onVideoCallPressed,
      readReceiptsEnabled: dm.readReceiptsEnabled,
      onMarkRead: (messageIds) => dmRepository.markMessagesRead(
        dmId: dm.dmId,
        roomId: roomId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      onHideMessages: (messageIds) => dmRepository.hideMessagesForMe(
        dmId: dm.dmId,
        roomId: roomId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      onEditMessage: (messageId, newContent) => dmRepository.editMessage(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
        newContent: newContent,
      ),
      onUnsendMessage: (messageId) => dmRepository.unsendMessage(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
      ),
      onSetReaction: (messageId, emoji) => dmRepository.setReaction(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
        userId: currentUser.userId,
        emoji: emoji,
      ),
      onDeclineAccountDeletionNotice: (messageId) =>
          dmRepository.declineAccountDeletionNotice(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
      ),
      onDeleteAfterAccountDeletion: () =>
          dmRepository.deleteDmAfterAccountDeletion(dm.dmId),
      onFetchMessagesAround: (messageId) => dmRepository.getMessagesAround(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
      ),
      extraActions: [
        _DmMenuButton(
          currentUser: currentUser,
          dm: dm,
          otherUserId: otherUserId,
          isBlocked: isBlocked,
        ),
      ],
      banner: (dm.severanceRequestedBy == null &&
              dm.readReceiptsProposalBy == null)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dm.severanceRequestedBy != null)
                  _SeveranceBanner(
                    currentUserId: currentUser.userId,
                    dm: dm,
                    otherUserId: otherUserId,
                  ),
                if (dm.readReceiptsProposalBy != null)
                  _ReadReceiptsProposalBanner(
                    currentUserId: currentUser.userId,
                    dm: dm,
                  ),
              ],
            ),
    );
  }
}

/// 絶縁の提案・同意待ちを常時表示するバナー（DmChatPaneの[ChatScreen.banner]に
/// 渡す）。提案した本人には「取り消す」、相手には「同意する／今は同意しない」
/// を出す。
class _SeveranceBanner extends ConsumerWidget {
  const _SeveranceBanner({
    required this.currentUserId,
    required this.dm,
    required this.otherUserId,
  });

  final String currentUserId;
  final DirectMessage dm;
  final String otherUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isProposedByMe = dm.severanceRequestedBy == currentUserId;

    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isProposedByMe
                    ? strings.severanceBannerWaitingForOther
                    : strings.severanceBannerProposedByOther,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            if (isProposedByMe)
              TextButton(
                onPressed: () => ref
                    .read(directMessageRepositoryProvider)
                    .cancelSeverance(dm.dmId),
                child: Text(strings.severanceBannerCancelButton),
              )
            else ...[
              TextButton(
                onPressed: () => ref
                    .read(directMessageRepositoryProvider)
                    .cancelSeverance(dm.dmId),
                child: Text(strings.severanceBannerDeclineButton),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                ),
                onPressed: () => SeveranceDialog.show(
                  context,
                  mode: SeveranceDialogMode.accept,
                  dmId: dm.dmId,
                  currentUserId: currentUserId,
                  otherUserId: otherUserId,
                ),
                child: Text(strings.severanceBannerAcceptButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 既読オン/オフの変更提案・承認待ちを常時表示するバナー（[_SeveranceBanner]
/// と同じ構造）。提案は常に現在の[DirectMessage.readReceiptsEnabled]を
/// 反転させることを意味するため、方向（オン/オフどちらへの提案か）は
/// `!dm.readReceiptsEnabled`から導出する。オフへの提案を承認する場合のみ、
/// 確定前に既読履歴が消える旨の確認ダイアログを挟む。
class _ReadReceiptsProposalBanner extends ConsumerWidget {
  const _ReadReceiptsProposalBanner({
    required this.currentUserId,
    required this.dm,
  });

  final String currentUserId;
  final DirectMessage dm;

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    bool turningOn,
  ) async {
    if (!turningOn) {
      final confirmed = await _confirmDisableReadReceipts(context, strings);
      if (!confirmed) return;
    }
    await ref.read(directMessageRepositoryProvider).acceptReadReceiptsToggle(
          dmId: dm.dmId,
          currentUserId: currentUserId,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isProposedByMe = dm.readReceiptsProposalBy == currentUserId;
    final turningOn = !dm.readReceiptsEnabled;
    final otherLabel = '@${dm.otherRhingId(currentUserId)}';

    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isProposedByMe
                    ? (turningOn
                        ? strings.conversationReadReceiptsBannerWaitingOn
                        : strings.conversationReadReceiptsBannerWaitingOff)
                    : (turningOn
                        ? strings.conversationReadReceiptsBannerProposedOn(otherLabel)
                        : strings.conversationReadReceiptsBannerProposedOff(otherLabel)),
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            if (isProposedByMe)
              TextButton(
                onPressed: () => ref
                    .read(directMessageRepositoryProvider)
                    .cancelReadReceiptsToggleProposal(dm.dmId),
                child: Text(strings.conversationReadReceiptsBannerCancelButton),
              )
            else ...[
              TextButton(
                onPressed: () => ref
                    .read(directMessageRepositoryProvider)
                    .cancelReadReceiptsToggleProposal(dm.dmId),
                child: Text(strings.conversationReadReceiptsBannerDeclineButton),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
                onPressed: () => _accept(context, ref, strings, turningOn),
                child: Text(strings.conversationReadReceiptsBannerAcceptButton),
              ),
            ],
          ],
        ),
      ),
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
    final vocabulary = ref.watch(vocabularyProvider);
    final prefs = ref
            .watch(conversationPrefsProvider(currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[dm.dmId]?.notificationsMuted ?? false;

    return PopupMenuButton<_DmMenuAction>(
      icon: const Icon(Icons.menu),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) async {
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
            // 既読オン/オフは一対共有の1つの設定で、どちら向きの変更も
            // 相手の承認が必要（提案は常に現在値の反転を意味する）。
            // オフにする提案の場合のみ、提案前に警告を出す。
            if (dm.readReceiptsEnabled) {
              final confirmed =
                  await _confirmDisableReadReceipts(context, strings);
              if (!confirmed) return;
            }
            ref.read(directMessageRepositoryProvider).proposeReadReceiptsToggle(
                  dmId: dm.dmId,
                  userId: currentUser.userId,
                );
          case _DmMenuAction.proposeSeverance:
            SeveranceDialog.show(
              context,
              mode: SeveranceDialogMode.propose,
              dmId: dm.dmId,
              currentUserId: currentUser.userId,
              otherUserId: otherUserId,
            );
          case _DmMenuAction.deleteConversation:
            final confirmed = await _confirmDeleteDm(context, strings);
            if (!confirmed) return;
            await ref
                .read(directMessageRepositoryProvider)
                .deleteDmAfterAccountDeletion(dm.dmId);
            if (context.mounted) {
              ref.read(goRouterProvider).go('/');
            }
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
        // 提案中（相手の承認待ち）は、この操作自体を無効化する
        // （二重提案を防ぐ。severanceの提案項目と同じ考え方）。
        PopupMenuItem(
          value: _DmMenuAction.toggleReadReceipts,
          enabled: dm.readReceiptsProposalBy == null,
          child: Text(
            dm.readReceiptsEnabled
                ? strings.conversationReadReceiptsProposeDisable
                : strings.conversationReadReceiptsProposeEnable,
          ),
        ),
        PopupMenuItem(
          value: _DmMenuAction.proposeSeverance,
          enabled: dm.severanceRequestedBy == null,
          child: Text(strings.conversationProposeSeverance),
        ),
        // 相手がアカウントを削除した場合のみ表示する（firestore.rulesの
        // deleteDmAfterAccountDeletion許可条件と同じ、
        // accountDeletedUserId != nullが根拠）。通知への「いいえ」応答後、
        // または未応答のままでも、ここからいつでも削除できる。
        if (dm.accountDeletedUserId != null)
          PopupMenuItem(
            value: _DmMenuAction.deleteConversation,
            child: Text(
              strings.dmMenuDeleteConversation(vocabulary.dm),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// 広場（グループ）のChatScreenを組み立てる。DmChatPaneと同じ理由で共通部品化。
class GroupChatPane extends ConsumerWidget {
  const GroupChatPane({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  /// 現在表示中の寄合。呼び出し側（TalksTab分割表示、または狭画面の
  /// 寄合一覧画面）が選択状態を管理し、渡す。
  final String roomId;
  final String roomName;

  /// メッセージの送信者アイコン・呼び名をタップした時に、相手のプロフィール
  /// カードを開く。一対と違い広場のメンバーは非友達の場合があるため、
  /// ここから友達申請できるようにする（メンバー一覧からも同じダイアログを開く、
  /// group_member_list_screen.dart参照）。
  Future<void> _openProfileCard(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final user = await ref.read(userRepositoryProvider).getUser(userId);
    if (user == null || !context.mounted) return;
    UserProfileCardDialog.show(context, currentUser: currentUser, user: user);
  }

  Future<void> _handleCallPressed(
    BuildContext context,
    WidgetRef ref, {
    required bool isVideo,
  }) async {
    final groupCallRepository = ref.read(groupCallRepositoryProvider);

    // 「進行中の通話を確認してから、無ければ新規作成する」という
    // 手順を2回のリクエストに分けてクライアント側で行うと、複数の
    // メンバーがほぼ同時に通話開始ボタンを押した場合にそれぞれが
    // 「進行中の通話は無い」と判定してしまい、別々の通話を作成して
    // 参加者がバラバラの通話に分かれてしまう不具合があった。
    // getOrCreateActiveGroupCallはFirestoreのトランザクションで
    // 「無ければ作る」を原子的に行うため、この競合が起きない。
    final call = await groupCallRepository.getOrCreateActiveGroupCall(
      group: group,
      initiator: currentUser,
      isVideo: isVideo,
    );

    final participants =
        await groupCallRepository.watchParticipants(call.groupCallId).first;
    if (participants.length >= call.maxParticipants) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('この通話は満員です（上限${call.maxParticipants}人）'),
          ),
        );
      }
      return;
    }

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
    // カスタムロール（見た目専用の呼び名フォントカラー）は広場全体・寄合ごとの
    // 付与を両方見る必要があるため、ロール一覧・寄合一覧をここでwatchして
    // 呼び名の色を解決する（`_SenderName`参照）。更新頻度が低いため
    // ネストしたStreamBuilderのコストは無視できる。
    return StreamBuilder<List<GroupRole>>(
      stream: groupRepository.watchRoles(group.groupId),
      builder: (context, rolesSnapshot) {
        final roles = {
          for (final role in rolesSnapshot.data ?? const <GroupRole>[])
            role.roleId: role,
        };
        return StreamBuilder<List<Room>>(
          stream: groupRepository.watchRooms(group.groupId),
          builder: (context, roomsSnapshot) {
            final rooms = roomsSnapshot.data ?? const <Room>[];
            final currentRoom = rooms.firstWhereOrNull((r) => r.roomId == roomId);
            Color? senderNameColorFor(String userId) {
              final assignedRoleId =
                  currentRoom?.roleAssignments[userId] ?? group.roleAssignments[userId];
              final role = assignedRoleId != null ? roles[assignedRoleId] : null;
              return role != null ? Color(0xFF000000 | role.color) : null;
            }

            return _buildChatScreen(
              context,
              ref,
              groupRepository,
              rooms,
              senderNameColorFor,
            );
          },
        );
      },
    );
  }

  Widget _buildChatScreen(
    BuildContext context,
    WidgetRef ref,
    GroupRepository groupRepository,
    List<Room> rooms,
    Color? Function(String userId) senderNameColorFor,
  ) {
    return ChatScreen(
      key: ValueKey('group-${group.groupId}-$roomId'),
      title: roomName,
      currentUserId: currentUser.userId,
      isDm: false,
      senderNameColorResolver: senderNameColorFor,
      // hiddenForに自分のuserIdが含まれるメッセージ（範囲選択削除で自分が
      // 削除したもの）は、他のメンバーには見えたままここでは表示しない。
      messagesStream: groupRepository
          .watchRoomMessages(group.groupId, roomId)
          .map((messages) => messages
              .where((m) => !m.hiddenFor.contains(currentUser.userId))
              .toList()),
      onSend: (content, {silent = false, replyTo}) => groupRepository.sendRoomMessage(
        groupId: group.groupId,
        roomId: roomId,
        senderId: currentUser.userId,
        senderRhingId: currentUser.rhingId,
        content: content,
        silent: silent,
        replyTo: replyTo,
      ),
      onCallPressed: () => _handleCallPressed(context, ref, isVideo: false),
      onVideoCallPressed: () => _handleCallPressed(context, ref, isVideo: true),
      readReceiptsEnabled: group.readReceiptsEnabled,
      onMarkRead: (messageIds) => groupRepository.markRoomMessagesRead(
        groupId: group.groupId,
        roomId: roomId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      onHideMessages: (messageIds) => groupRepository.hideRoomMessagesForMe(
        groupId: group.groupId,
        roomId: roomId,
        userId: currentUser.userId,
        messageIds: messageIds,
      ),
      onEditMessage: (messageId, newContent) => groupRepository.editRoomMessage(
        groupId: group.groupId,
        roomId: roomId,
        messageId: messageId,
        newContent: newContent,
      ),
      onUnsendMessage: (messageId) => groupRepository.unsendRoomMessage(
        groupId: group.groupId,
        roomId: roomId,
        messageId: messageId,
      ),
      onSetReaction: (messageId, emoji) => groupRepository.setRoomMessageReaction(
        groupId: group.groupId,
        roomId: roomId,
        messageId: messageId,
        userId: currentUser.userId,
        emoji: emoji,
      ),
      onFetchMessagesAround: (messageId) => groupRepository.getRoomMessagesAround(
        groupId: group.groupId,
        roomId: roomId,
        messageId: messageId,
      ),
      extraActions: [
        _GroupMenuButton(
          currentUser: currentUser,
          group: group,
          roomId: roomId,
          roomName: roomName,
        ),
      ],
      onSenderTap: (userId) => _openProfileCard(context, ref, userId),
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
  const _GroupMenuButton({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
  });

  final AppUser currentUser;
  final Group group;

  /// 現在表示中の寄合。カスタムロールの寄合ごとの付与（メンバー一覧
  /// ポップアップの「この寄合のみ」切り替え）に使う。
  final String roomId;
  final String roomName;

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
                  roomId: widget.roomId,
                  roomName: widget.roomName,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ロール一覧ポップアップも、メンバー一覧ポップアップと同じくボタンの
  // 左隣に表示する。
  Future<void> _showRoleListPopup() {
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
                child: GroupRoleListPopup(groupId: widget.group.groupId),
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
    final isOwnerOrModerator = isOwner ||
        widget.group.memberRoles[widget.currentUser.userId] == 'moderator';
    final prefs = ref
            .watch(conversationPrefsProvider(widget.currentUser.userId))
            .value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[widget.group.groupId]?.notificationsMuted ?? false;
    final readReceiptsEnabled = widget.group.readReceiptsEnabled;

    return PopupMenuButton<_GroupMenuAction>(
      key: _buttonKey,
      icon: const Icon(Icons.menu),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) async {
        switch (action) {
          case _GroupMenuAction.profileCard:
            _showProfileCardPopup();
          case _GroupMenuAction.memberList:
            _showMemberListPopup();
          case _GroupMenuAction.createInvite:
            GroupInviteDialog.show(
              context,
              widget.group.groupId,
              widget.group.profileCard,
            );
          case _GroupMenuAction.manageRoles:
            if (!isOwnerOrModerator) return;
            _showRoleListPopup();
          case _GroupMenuAction.toggleMute:
            ref.read(conversationPrefsRepositoryProvider).setNotificationsMuted(
                  userId: widget.currentUser.userId,
                  conversationId: widget.group.groupId,
                  muted: !muted,
                );
          case _GroupMenuAction.toggleReadReceipts:
            // 既読機能のオン/オフは長のみ操作可能（firestore.rulesで強制、
            // メニュー項目自体もisOwnerでない限りenabled: falseにしている）。
            // オフにする場合のみ、確定前に既読履歴が消える旨を警告する。
            if (!isOwner) return;
            if (readReceiptsEnabled) {
              final confirmed =
                  await _confirmDisableReadReceipts(context, strings);
              if (!confirmed) return;
            }
            ref.read(groupRepositoryProvider).setReadReceiptsEnabled(
                  groupId: widget.group.groupId,
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
        // カスタムロール（見た目専用の呼び名色分け機能）の作成・色設定・
        // 付与は長・モデレーターのみ（2026-07-28追加）。
        PopupMenuItem(
          value: _GroupMenuAction.manageRoles,
          enabled: isOwnerOrModerator,
          child: Text(strings.groupMenuManageRoles),
        ),
        PopupMenuItem(
          value: _GroupMenuAction.toggleMute,
          child: Text(muted ? strings.conversationUnmute : strings.conversationMute),
        ),
        // 既読機能のオン/オフは長のみ操作可能。長以外には現在の状態を
        // 示すラベルとして表示するが、操作はできない（leaveがisOwnerで
        // 無効化されているのと同じ考え方）。
        PopupMenuItem(
          value: _GroupMenuAction.toggleReadReceipts,
          enabled: isOwner,
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
