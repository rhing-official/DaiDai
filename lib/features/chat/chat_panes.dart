import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/day_messages_page.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/group_repository.dart';
import '../../router/app_router.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/group_permissions.dart';
import '../../utils/platform_info.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../call/active_call_session.dart';
import '../call/embedded_call_pane.dart';
import 'chat_screen.dart';
import 'conversation_profile_card_dialog.dart';
import 'group_delete_dialog.dart';
import 'group_invite_dialog.dart';
import 'group_leave_dialog.dart';
import 'group_member_list_screen.dart';
import 'group_profile_card_screen.dart';
import 'group_role_list_popup.dart';
import 'group_role_priority_dialog.dart';
import 'room_tab_bar.dart';
import 'severance_dialog.dart';
import 'user_profile_card_dialog.dart';

enum _GroupMenuAction {
  profileCard,
  conversationProfileCard,
  memberList,
  createInvite,
  manageRoles,
  deleteGroup,
  roomRolePriority,
  renameRoom,
  deleteRoom,
  enableMultipleRooms,
  toggleMute,
  toggleReadReceipts,
  leave,
}

enum _DmMenuAction {
  conversationProfileCard,
  renameRoom,
  deleteRoom,
  enableMultipleRooms,
  toggleMute,
  toggleBlock,
  toggleReadReceipts,
  proposeSeverance,
  deleteConversation,
}

/// 既読機能をオフにする方向の操作（広場: 長が直接オフにする／DM: オフを
/// 提案する・オフの提案を承認する）から共通で呼ぶ確認ダイアログ。
/// `chat_screen.dart`の`_confirmUnsend`と同じ、キャンセル/エラー色ボタンの形。
Future<bool> confirmDisableReadReceipts(
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

/// 寄合の名前変更ダイアログ。広場・一対どちらのハンバーガーメニューからも
/// 同じ見た目で使う（[RoomListPane]の寄合追加ダイアログと同じ、名前入力
/// フィールド1つのシンプルな構成）。キャンセル・空欄のままの保存はnullを返す。
Future<String?> _showRenameRoomDialog(
  BuildContext context,
  Strings strings,
  Vocabulary vocab,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.roomRenameLabel(vocab.textChannel)),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(strings.save),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}

/// 寄合の削除確認ダイアログ。広場・一対どちらのハンバーガーメニューからも
/// 同じ見た目で使う（旧: 寄合一覧サイドバーのごみ箱アイコンから同じ文言・
/// 見た目で出していたものを、2026-07-30にハンバーガーメニューへ移設）。
Future<bool> _confirmDeleteRoom(
  BuildContext context,
  Strings strings,
  Vocabulary vocab,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.roomListDeleteConfirmTitle(vocab.textChannel)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          // colorScheme.errorはダークテーマ下ではMaterial3の仕様上
          // 明るめのサーモンピンクに近い色になり「濃い赤」に見えなかった
          // ため、固定の濃い赤に変更する（2026-08-12）。
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.roomListDeleteConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 一対（DM）のChatScreenを組み立てる。相手のアクティブなニックネームを
/// タイトルに反映するためConsumer化している。go_routerのフルスクリーン遷移と、
/// TalksTabの分割ビュー（一覧の右隣に埋め込み表示）の両方から使う共通部品。
/// メッセージの1日単位ページネーション（2026-08-20追加）の状態
/// （購読・読み込み済みの過去日）を自分自身のStateで保持するため
/// `ConsumerStatefulWidget`にしている（`DmChatPane`が破棄されない限り
/// ページネーション状態も保持され続ける。`TalksTab`の会話ペインキャッシュ
/// と組み合わせることで、会話を切り替えても読み込み直しが起きなくなる）。
class DmChatPane extends ConsumerStatefulWidget {
  const DmChatPane({
    required this.currentUser,
    required this.dm,
    required this.roomId,
    required this.roomName,
    this.onCallPressed,
    this.onVideoCallPressed,
    this.showRoomTabBar = false,
    this.onSwipeBack,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;

  /// 現在表示中の寄合。呼び出し側（TalksTab分割表示、またはgo_routerの
  /// フルスクリーン遷移）が選択状態を管理し、渡す。
  final String roomId;
  final String roomName;

  final VoidCallback? onCallPressed;
  final VoidCallback? onVideoCallPressed;

  /// AppBar直下に寄合の横スクロールタブバー（`RoomTabBar`）を表示するか
  /// （2026-08-03追加）。trueでも[DirectMessage.roomsEnabled]がfalseの
  /// 単一モードでは表示しない。TalksTabの分割表示（サイドバー使用中）からは
  /// falseのまま渡す（サイドバーと二重にならないように）。
  final bool showRoomTabBar;

  /// 縦表示（`/chat/dm`ルート）で、吹き出しの上を右スワイプした時に会話一覧へ
  /// 戻る処理（2026-08-06追加、`ChatScreen.onSwipeBack`参照）。[showRoomTabBar]
  /// と同じ「ルート経由か広い画面への埋め込みか」の基準で、TalksTabの分割
  /// 表示からはnullのまま渡す（会話一覧へ戻る概念が無いため）。
  final VoidCallback? onSwipeBack;

  @override
  ConsumerState<DmChatPane> createState() => _DmChatPaneState();
}

class _DmChatPaneState extends ConsumerState<DmChatPane> {
  /// `ChatScreen.messagesStream`へ渡すstream本体（2026-08-20追加）。
  /// `Stream.value(...)`をbuild()のたびに新規生成すると、streamの
  /// identityが変わるたびに`ChatScreen`側の`StreamBuilder`が再購読して
  /// `ConnectionState.waiting`に戻り、メッセージ一覧の`ListView`（＝
  /// スクロール位置）ごと一瞬破棄・再構築されてしまう（1日単位
  /// ページネーションのスクロール読み込みが、読み込み直後の再構築で
  /// スクロール位置を最新側へ戻されてしまい機能しなかった不具合の原因）。
  /// `initState`で一度だけ生成し、値の更新は`.add()`で流し込むことで
  /// stream自体のidentityを固定し、`ListView`のScrollableを再構築させない。
  final _messagesController = StreamController<List<Message>>.broadcast();

  /// 直近の活動日1日分のライブ購読分（メッセージの1日単位ページネーション、
  /// 2026-08-20追加）。
  List<Message> _liveTailMessages = const [];

  /// [_loadOlderMessages]で読み込んだ、直近の活動日より古い日の蓄積分。
  final List<Message> _olderMessages = [];

  /// 次に[_loadOlderMessages]を呼ぶ際の境界（現在読み込み済みの最も古い日の
  /// 開始時刻）。`watchLatestDayMessages`の初回応答で確定する。
  DateTime? _oldestLoadedDayStart;

  bool _isLoadingOlder = false;
  bool _hasMoreHistory = true;

  StreamSubscription<DayMessagesPage>? _tailSub;

  @override
  void initState() {
    super.initState();
    _subscribeTail();
  }

  void _subscribeTail() {
    _tailSub = ref
        .read(directMessageRepositoryProvider)
        .watchLatestDayMessages(widget.dm.dmId, widget.roomId)
        .listen((page) {
          if (!mounted) return;
          setState(() {
            _liveTailMessages = page.messages;
            _oldestLoadedDayStart ??= page.dayStart;
          });
        });
  }

  Future<void> _loadOlderMessages() async {
    final boundary = _oldestLoadedDayStart;
    if (_isLoadingOlder || !_hasMoreHistory || boundary == null) return;
    setState(() => _isLoadingOlder = true);
    final page = await ref
        .read(directMessageRepositoryProvider)
        .loadOlderDayMessages(
          dmId: widget.dm.dmId,
          roomId: widget.roomId,
          beforeDayStart: boundary,
        );
    if (!mounted) return;
    setState(() {
      _isLoadingOlder = false;
      if (page == null) {
        _hasMoreHistory = false;
      } else {
        _olderMessages.addAll(page.messages);
        _oldestLoadedDayStart = page.dayStart;
      }
    });
  }

  @override
  void dispose() {
    _tailSub?.cancel();
    _messagesController.close();
    super.dispose();
  }

  /// メッセージの送信者アイコン・呼び名をタップした時に、相手のプロフィール
  /// カードを開く（広場側の`GroupChatPane._openProfileCard`と同じ導線）。
  Future<void> _openProfileCard(BuildContext context, String userId) async {
    final user = await ref.read(userRepositoryProvider).getUser(userId);
    if (user == null || !context.mounted) return;
    UserProfileCardDialog.show(
      context,
      currentUser: widget.currentUser,
      user: user,
      conversationId: widget.dm.dmId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 通話中、PC/Webではこの会話を表示している間だけメッセージ一覧の
    // 代わりに通話UIを埋め込み表示する（2026-08-19追加、EmbeddedCallPane
    // 参照）。
    return EmbeddedCallPane(
      conversation: ViewedDm(widget.dm.dmId),
      conversationTitle: widget.roomName,
      child: Builder(
        builder: (context) {
          // 横スクロールタブバーはこの寄合一覧を必要とする場合のみ購読する
          // （単一モードや広い画面のサイドバー使用中は不要な購読を増やさない）。
          if (!widget.showRoomTabBar || !widget.dm.roomsEnabled) {
            return _buildChatScreen(context, null);
          }
          return StreamBuilder<List<DmRoom>>(
            stream: ref
                .read(directMessageRepositoryProvider)
                .watchRooms(
                  dmId: widget.dm.dmId,
                  userId: widget.currentUser.userId,
                ),
            builder: (context, snapshot) =>
                _buildChatScreen(context, snapshot.data ?? const <DmRoom>[]),
          );
        },
      ),
    );
  }

  Widget _buildChatScreen(BuildContext context, List<DmRoom>? rooms) {
    final strings = ref.watch(appStringsProvider);
    final dmRepository = ref.watch(directMessageRepositoryProvider);
    final dm = widget.dm;
    final currentUser = widget.currentUser;
    final roomId = widget.roomId;
    final roomName = widget.roomName;
    final otherUserId = dm.otherUserId(currentUser.userId);
    final blockedIds =
        ref.watch(blockedUserIdsProvider(currentUser.userId)).value ?? const {};
    final isBlocked = blockedIds.contains(otherUserId);
    // ブロック中は相手からのメッセージを表示しない（自分が送った過去分は
    // 引き続き見える）。サーバー側の送信拒否ではなく、クライアント側の
    // 表示抑制で実現する（`BlockRepository`のコメント参照）。
    // hiddenForに自分のuserIdが含まれるメッセージ（範囲選択削除で自分が
    // 削除したもの）も、相手には見えたままここでは表示しないだけにする。
    final combined = <Message>[..._liveTailMessages, ..._olderMessages]
      ..sort(
        (a, b) => (b.sentAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.sentAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    final filteredMessages = combined
        .where((m) => !m.hiddenFor.contains(currentUser.userId))
        .where((m) => !isBlocked || m.senderId != otherUserId)
        .toList();
    // messagesStreamに渡すstream自体のidentityを固定するため、値は
    // `_messagesController`へ流し込む（`_messagesController`のdocコメント
    // 参照）。
    _messagesController.add(filteredMessages);
    return ChatScreen(
      key: ValueKey('dm-${dm.dmId}-$roomId'),
      title: roomName,
      onSwipeBack: widget.onSwipeBack,
      roomTabBar: rooms == null
          ? null
          : RoomTabBar(
              rooms: [for (final r in rooms) (roomId: r.roomId, name: r.name)],
              selectedRoomId: roomId,
              onSelectRoom: (room) => ref
                  .read(goRouterProvider)
                  .pushReplacement(
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
      currentUserId: currentUser.userId,
      isDm: true,
      conversationId: dm.dmId,
      roomId: roomId,
      onSenderTap: (userId) => _openProfileCard(context, userId),
      messagesStream: _messagesController.stream,
      onLoadOlderMessages: _loadOlderMessages,
      isLoadingOlderMessages: _isLoadingOlder,
      hasMoreHistory: _hasMoreHistory,
      onSend: (content, {silent = false, replyTo}) async {
        if (isBlocked) {
          showAutoDismissBanner(
            context,
            message: strings.conversationBlockedCannotSend,
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
      onSendAttachment: (attachment) async {
        if (isBlocked) {
          showAutoDismissBanner(
            context,
            message: strings.conversationBlockedCannotSend,
          );
          return;
        }
        await dmRepository.sendAttachmentMessage(
          dmId: dm.dmId,
          roomId: roomId,
          senderId: currentUser.userId,
          senderRhingId: currentUser.rhingId,
          bytes: attachment.bytes,
          fileName: attachment.fileName,
          contentType: attachment.contentType,
        );
      },
      onSendSticker: (sticker) async {
        if (isBlocked) {
          showAutoDismissBanner(
            context,
            message: strings.conversationBlockedCannotSend,
          );
          return;
        }
        await dmRepository.sendStickerMessage(
          dmId: dm.dmId,
          roomId: roomId,
          senderId: currentUser.userId,
          senderRhingId: currentUser.rhingId,
          stickerId: sticker.stickerId,
          stickerName: sticker.name,
          stickerUrl: sticker.imageUrl,
        );
      },
      onCallPressed: widget.onCallPressed,
      onVideoCallPressed: widget.onVideoCallPressed,
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
      onSetReaction: (messageId, emojis) => dmRepository.setReaction(
        dmId: dm.dmId,
        roomId: roomId,
        messageId: messageId,
        userId: currentUser.userId,
        emojis: emojis,
      ),
      onDeclineAccountDeletionNotice: (messageId) =>
          dmRepository.declineAccountDeletionNotice(
            dmId: dm.dmId,
            roomId: roomId,
            messageId: messageId,
          ),
      onDeleteAfterAccountDeletion: () => dmRepository
          .deleteDmAfterAccountDeletion(dm.dmId, userId: currentUser.userId),
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
          roomId: roomId,
          roomName: roomName,
        ),
      ],
      banner:
          (dm.severanceRequestedBy == null && dm.readReceiptsProposalBy == null)
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
      final confirmed = await confirmDisableReadReceipts(context, strings);
      if (!confirmed) return;
    }
    await ref
        .read(directMessageRepositoryProvider)
        .acceptReadReceiptsToggle(dmId: dm.dmId, currentUserId: currentUserId);
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
                          ? strings.conversationReadReceiptsBannerProposedOn(
                              otherLabel,
                            )
                          : strings.conversationReadReceiptsBannerProposedOff(
                              otherLabel,
                            )),
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
                child: Text(
                  strings.conversationReadReceiptsBannerDeclineButton,
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                ),
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
    required this.roomId,
    required this.roomName,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final String otherUserId;
  final bool isBlocked;

  /// 現在表示中の寄合（名前変更の対象）。
  final String roomId;
  final String roomName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocabulary = ref.watch(vocabularyProvider);
    final prefs =
        ref.watch(conversationPrefsProvider(currentUser.userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[dm.dmId]?.notificationsMuted ?? false;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    return PopupMenuButton<_DmMenuAction>(
      icon: isGekiga
          ? const GekigaIconBadge(icon: Icons.menu, size: 36)
          : const Icon(Icons.menu),
      tooltip: '',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) async {
        switch (action) {
          case _DmMenuAction.conversationProfileCard:
            ConversationProfileCardDialog.show(
              context,
              currentUserId: currentUser.userId,
              conversationId: dm.dmId,
            );
          case _DmMenuAction.renameRoom:
            final name = await _showRenameRoomDialog(
              context,
              strings,
              vocabulary,
              roomName,
            );
            if (name == null) return;
            await ref
                .read(directMessageRepositoryProvider)
                .renameRoom(dmId: dm.dmId, roomId: roomId, name: name);
          case _DmMenuAction.deleteRoom:
            final confirmed = await _confirmDeleteRoom(
              context,
              strings,
              vocabulary,
            );
            if (!confirmed) return;
            try {
              await ref
                  .read(directMessageRepositoryProvider)
                  .deleteRoom(
                    dmId: dm.dmId,
                    roomId: roomId,
                    requestedBy: currentUser.userId,
                  );
            } on StateError {
              if (context.mounted) {
                showAutoDismissBanner(
                  context,
                  message: strings.roomDeleteLastRoomError,
                );
              }
              return;
            }
            if (!context.mounted) return;
            if (Navigator.of(context).canPop()) {
              // 狭い画面（フルスクリーンpush）: 語らい一覧へ戻すのではなく、
              // 一番上（最古）の寄合を開き直す。最後の1つの寄合は削除
              // できない仕様のため、削除後リストが空になることはない
              // （2026-08-13追加）。
              final remainingRooms = await ref
                  .read(directMessageRepositoryProvider)
                  .watchRooms(dmId: dm.dmId, userId: currentUser.userId)
                  .first;
              if (!context.mounted) return;
              if (remainingRooms.isNotEmpty) {
                final topRoom = remainingRooms.first;
                ref
                    .read(goRouterProvider)
                    .pushReplacement(
                      '/chat/dm',
                      extra: DmChatArgs(
                        currentUser: currentUser,
                        dm: dm,
                        roomId: topRoom.roomId,
                        roomName: topRoom.name,
                      ),
                    );
              } else {
                Navigator.of(context).pop();
              }
            }
          // 広い画面（埋め込みペイン）はcanPop()==falseで元々no-op。
          // TalksTab側の既存フォールバック（rooms.first）が自動的に
          // 一番上の寄合を選択するため、追加対応不要。
          case _DmMenuAction.enableMultipleRooms:
            await ref
                .read(directMessageRepositoryProvider)
                .setRoomsEnabled(dm.dmId);
          case _DmMenuAction.toggleMute:
            ref
                .read(conversationPrefsRepositoryProvider)
                .setNotificationsMuted(
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
              final confirmed = await confirmDisableReadReceipts(
                context,
                strings,
              );
              if (!confirmed) return;
            }
            ref
                .read(directMessageRepositoryProvider)
                .proposeReadReceiptsToggle(
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
                .deleteDmAfterAccountDeletion(
                  dm.dmId,
                  userId: currentUser.userId,
                );
            if (context.mounted) {
              ref.read(goRouterProvider).go('/');
            }
        }
      },
      itemBuilder: (context) => [
        if (currentUser.profileCards.length > 1)
          PopupMenuItem(
            value: _DmMenuAction.conversationProfileCard,
            child: Text(strings.conversationProfileCardMenuLabel),
          ),
        PopupMenuItem(
          value: _DmMenuAction.renameRoom,
          child: Text(strings.roomRenameLabel(vocabulary.textChannel)),
        ),
        // 寄合一覧サイドバーのごみ箱アイコンの代わり（2026-07-30変更）。
        // 最後の1つの寄合は選べても実際には削除できず、リポジトリが
        // StateErrorを投げてSnackBarで案内する（`onSelected`参照）。
        PopupMenuItem(
          value: _DmMenuAction.deleteRoom,
          child: Text(
            strings.roomMenuDeleteLabel(vocabulary.textChannel),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        // 単一モードの間だけ「寄合を増やす」を出す。複数モードへの切り替えは
        // 一方向のみ（2026-07-29追加、`DirectMessage.roomsEnabled`参照）。
        if (!dm.roomsEnabled)
          PopupMenuItem(
            value: _DmMenuAction.enableMultipleRooms,
            child: Text(strings.dmMenuEnableMultipleRooms),
          ),
        PopupMenuItem(
          value: _DmMenuAction.toggleMute,
          child: Text(
            muted ? strings.conversationUnmute : strings.conversationMute,
          ),
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
/// メッセージの1日単位ページネーション（2026-08-20追加）の状態を自分自身の
/// Stateで保持するため`ConsumerStatefulWidget`にしている（`DmChatPane`と
/// 同じ理由、コメント参照）。
class GroupChatPane extends ConsumerStatefulWidget {
  const GroupChatPane({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = false,
    this.onSwipeBack,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  /// 現在表示中の寄合。呼び出し側（TalksTab分割表示、またはgo_routerの
  /// フルスクリーン遷移）が選択状態を管理し、渡す。
  final String roomId;
  final String roomName;

  /// AppBar直下に寄合の横スクロールタブバー（`RoomTabBar`）を表示するか
  /// （2026-08-03追加）。trueでも[Group.roomsEnabled]がfalseの単一モードでは
  /// 表示しない。TalksTabの分割表示（サイドバー使用中）からはfalseのまま渡す
  /// （サイドバーと二重にならないように）。
  final bool showRoomTabBar;

  /// 縦表示（`/chat/group`ルート）で、吹き出しの上を右スワイプした時に会話
  /// 一覧へ戻る処理（2026-08-06追加、`ChatScreen.onSwipeBack`参照）。
  /// [showRoomTabBar]と同じ基準で、TalksTabの分割表示からはnullのまま渡す。
  final VoidCallback? onSwipeBack;

  @override
  ConsumerState<GroupChatPane> createState() => _GroupChatPaneState();
}

class _GroupChatPaneState extends ConsumerState<GroupChatPane> {
  /// `ChatScreen.messagesStream`へ渡すstream本体（2026-08-20追加）。
  /// `DmChatPane`の同名フィールドと同じ理由（`_DmChatPaneState
  /// ._messagesController`のdocコメント参照）で、stream自体のidentityを
  /// `initState`から`dispose`まで固定するために使う。
  final _messagesController = StreamController<List<Message>>.broadcast();

  /// 直近の活動日1日分のライブ購読分（メッセージの1日単位ページネーション、
  /// 2026-08-20追加）。
  List<Message> _liveTailMessages = const [];

  /// [_loadOlderMessages]で読み込んだ、直近の活動日より古い日の蓄積分。
  final List<Message> _olderMessages = [];

  /// 次に[_loadOlderMessages]を呼ぶ際の境界（現在読み込み済みの最も古い日の
  /// 開始時刻）。`watchLatestDayRoomMessages`の初回応答で確定する。
  DateTime? _oldestLoadedDayStart;

  bool _isLoadingOlder = false;
  bool _hasMoreHistory = true;

  StreamSubscription<DayMessagesPage>? _tailSub;

  @override
  void initState() {
    super.initState();
    _subscribeTail();
  }

  void _subscribeTail() {
    _tailSub = ref
        .read(groupRepositoryProvider)
        .watchLatestDayRoomMessages(widget.group.groupId, widget.roomId)
        .listen((page) {
          if (!mounted) return;
          setState(() {
            _liveTailMessages = page.messages;
            _oldestLoadedDayStart ??= page.dayStart;
          });
        });
  }

  Future<void> _loadOlderMessages() async {
    final boundary = _oldestLoadedDayStart;
    if (_isLoadingOlder || !_hasMoreHistory || boundary == null) return;
    setState(() => _isLoadingOlder = true);
    final page = await ref
        .read(groupRepositoryProvider)
        .loadOlderRoomDayMessages(
          groupId: widget.group.groupId,
          roomId: widget.roomId,
          beforeDayStart: boundary,
        );
    if (!mounted) return;
    setState(() {
      _isLoadingOlder = false;
      if (page == null) {
        _hasMoreHistory = false;
      } else {
        _olderMessages.addAll(page.messages);
        _oldestLoadedDayStart = page.dayStart;
      }
    });
  }

  @override
  void dispose() {
    _tailSub?.cancel();
    _messagesController.close();
    super.dispose();
  }

  /// メッセージの送信者アイコン・呼び名をタップした時に、相手のプロフィール
  /// カードを開く。一対と違い広場のメンバーは非友達の場合があるため、
  /// ここから友達申請できるようにする（メンバー一覧からも同じダイアログを開く、
  /// group_member_list_screen.dart参照）。
  Future<void> _openProfileCard(BuildContext context, String userId) async {
    final user = await ref.read(userRepositoryProvider).getUser(userId);
    if (user == null || !context.mounted) return;
    UserProfileCardDialog.show(
      context,
      currentUser: widget.currentUser,
      user: user,
      conversationId: widget.group.groupId,
    );
  }

  Future<void> _handleCallPressed(
    BuildContext context, {
    required bool isVideo,
  }) async {
    final group = widget.group;
    final currentUser = widget.currentUser;
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

    final participants = await groupCallRepository
        .watchParticipants(call.groupCallId)
        .first;
    if (participants.length >= call.maxParticipants) {
      if (context.mounted) {
        showAutoDismissBanner(
          context,
          message: 'この通話は満員です（上限${call.maxParticipants}人）',
        );
      }
      return;
    }

    if (!context.mounted) return;
    // モバイルのみ全画面の/group-callへpushする。PCでは全画面ルートを
    // 使わず、通話セッションを直接開始するだけにする（2026-08-19変更）。
    // 発信者は既にこの広場のメッセージ画面を見ているため、以後は
    // `EmbeddedCallPane`がそのメッセージ画面内に埋め込み表示として引き継ぐ。
    if (isMobileCallPlatform) {
      ref
          .read(goRouterProvider)
          .push(
            '/group-call',
            extra: GroupCallArgs(
              groupCallId: call.groupCallId,
              groupId: group.groupId,
              currentUser: currentUser,
              isVideo: call.isVideo,
            ),
          );
      return;
    }
    ref
        .read(activeCallSessionProvider.notifier)
        .startGroup(
          groupCallId: call.groupCallId,
          groupId: group.groupId,
          currentUser: currentUser,
          isVideo: call.isVideo,
          groupCallRepository: groupCallRepository,
        );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final currentUser = widget.currentUser;
    final roomId = widget.roomId;
    final groupRepository = ref.watch(groupRepositoryProvider);
    // 通話中、PC/Webではこの会話を表示している間だけメッセージ一覧の
    // 代わりに通話UIを埋め込み表示する（2026-08-19追加、EmbeddedCallPane
    // 参照）。
    return EmbeddedCallPane(
      conversation: ViewedGroup(group.groupId),
      conversationTitle: widget.roomName,
      child: Builder(
        builder: (context) {
          // カスタムロール（見た目専用の呼び名フォントカラー）は広場全体の
          // 優先順位・寄合ごとの上書きを両方見る必要があるため、ロール
          // 一覧・寄合一覧をここでwatchして呼び名の色を解決する
          // （`resolveSenderColor`/`_SenderName`参照）。更新頻度が低いため
          // ネストしたStreamBuilderのコストは無視できる。
          return StreamBuilder<List<GroupRole>>(
            stream: groupRepository.watchRoles(group.groupId),
            builder: (context, rolesSnapshot) {
              final roles = rolesSnapshot.data ?? const <GroupRole>[];
              return StreamBuilder<List<Room>>(
                stream: groupRepository.watchRooms(
                  groupId: group.groupId,
                  userId: currentUser.userId,
                ),
                builder: (context, roomsSnapshot) {
                  final rooms = roomsSnapshot.data ?? const <Room>[];
                  final currentRoom = rooms.firstWhereOrNull(
                    (r) => r.roomId == roomId,
                  );
                  Color? senderNameColorFor(String userId) =>
                      resolveSenderColor(
                        group: group,
                        currentRoom: currentRoom,
                        roles: roles,
                        userId: userId,
                      );

                  return _buildChatScreen(
                    context,
                    groupRepository,
                    rooms,
                    currentRoom,
                    roles,
                    senderNameColorFor,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChatScreen(
    BuildContext context,
    GroupRepository groupRepository,
    List<Room> rooms,
    Room? currentRoom,
    List<GroupRole> roles,
    Color? Function(String userId) senderNameColorFor,
  ) {
    final group = widget.group;
    final currentUser = widget.currentUser;
    final roomId = widget.roomId;
    final roomName = widget.roomName;
    final canManageRooms = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageRooms,
    );
    // hiddenForに自分のuserIdが含まれるメッセージ（範囲選択削除で自分が
    // 削除したもの）は、他のメンバーには見えたままここでは表示しない。
    final combined = <Message>[..._liveTailMessages, ..._olderMessages]
      ..sort(
        (a, b) => (b.sentAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.sentAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    final filteredMessages = combined
        .where((m) => !m.hiddenFor.contains(currentUser.userId))
        .toList();
    // messagesStreamに渡すstream自体のidentityを固定するため、値は
    // `_messagesController`へ流し込む（`_messagesController`のdocコメント
    // 参照）。
    _messagesController.add(filteredMessages);
    return ChatScreen(
      key: ValueKey('group-${group.groupId}-$roomId'),
      title: roomName,
      onSwipeBack: widget.onSwipeBack,
      currentUserId: currentUser.userId,
      isDm: false,
      conversationId: group.groupId,
      roomId: roomId,
      senderNameColorResolver: senderNameColorFor,
      roomTabBar: !widget.showRoomTabBar || !group.roomsEnabled
          ? null
          : RoomTabBar(
              rooms: [for (final r in rooms) (roomId: r.roomId, name: r.name)],
              selectedRoomId: roomId,
              onSelectRoom: (room) => ref
                  .read(goRouterProvider)
                  .pushReplacement(
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
            ),
      messagesStream: _messagesController.stream,
      onLoadOlderMessages: _loadOlderMessages,
      isLoadingOlderMessages: _isLoadingOlder,
      hasMoreHistory: _hasMoreHistory,
      onSend: (content, {silent = false, replyTo}) =>
          groupRepository.sendRoomMessage(
            groupId: group.groupId,
            roomId: roomId,
            senderId: currentUser.userId,
            senderRhingId: currentUser.rhingId,
            content: content,
            silent: silent,
            replyTo: replyTo,
          ),
      onSendAttachment: (attachment) => groupRepository.sendAttachmentMessage(
        groupId: group.groupId,
        roomId: roomId,
        senderId: currentUser.userId,
        senderRhingId: currentUser.rhingId,
        bytes: attachment.bytes,
        fileName: attachment.fileName,
        contentType: attachment.contentType,
      ),
      onSendSticker: (sticker) => groupRepository.sendStickerMessage(
        groupId: group.groupId,
        roomId: roomId,
        senderId: currentUser.userId,
        senderRhingId: currentUser.rhingId,
        stickerId: sticker.stickerId,
        stickerName: sticker.name,
        stickerUrl: sticker.imageUrl,
      ),
      onCallPressed: () => _handleCallPressed(context, isVideo: false),
      onVideoCallPressed: () => _handleCallPressed(context, isVideo: true),
      readReceiptsEnabled: effectiveReadReceiptsEnabled(
        group: group,
        room: currentRoom,
      ),
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
      onSetReaction: (messageId, emojis) =>
          groupRepository.setRoomMessageReaction(
            groupId: group.groupId,
            roomId: roomId,
            messageId: messageId,
            userId: currentUser.userId,
            emojis: emojis,
          ),
      onFetchMessagesAround: (messageId) =>
          groupRepository.getRoomMessagesAround(
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
          currentRoom: currentRoom,
          roles: roles,
        ),
      ],
      onSenderTap: (userId) => _openProfileCard(context, userId),
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
    required this.currentRoom,
    required this.roles,
  });

  final AppUser currentUser;
  final Group group;

  /// 現在表示中の寄合。
  final String roomId;
  final String roomName;

  /// [roomId]が指す寄合のドキュメント本体（`rolePriorityOverride`の現在値の
  /// 表示・編集に使う）。ロード中でまだ取得できていない場合はnull。
  final Room? currentRoom;

  /// この広場のカスタムロール一覧（優先順位並べ替えダイアログに渡す）。
  final List<GroupRole> roles;

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
        final left = (buttonRect.left - width).clamp(
          8.0,
          screenSize.width - width - 8.0,
        );
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
                  roles: widget.roles,
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
    final vocabulary = ref.watch(vocabularyProvider);
    final userId = widget.currentUser.userId;
    final isOwner = widget.group.ownerId == userId;
    final canManageRoles = hasGroupPermission(
      group: widget.group,
      userId: userId,
      permission: GroupPermission.manageRoles,
    );
    final canManageReadReceipts = hasGroupPermission(
      group: widget.group,
      userId: userId,
      permission: GroupPermission.manageReadReceipts,
    );
    final canCreateInvite = hasGroupPermission(
      group: widget.group,
      userId: userId,
      permission: GroupPermission.createInvite,
    );
    final canManageRooms = hasGroupPermission(
      group: widget.group,
      userId: userId,
      permission: GroupPermission.manageRooms,
    );
    final prefs =
        ref.watch(conversationPrefsProvider(widget.currentUser.userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[widget.group.groupId]?.notificationsMuted ?? false;
    final readReceiptsEnabled = widget.group.readReceiptsEnabled;
    // 「この寄合独自の設定」がオンの間だけ、通知・既読はこの寄合専用の値を
    // 使う（広場全体の値より優先、2026-07-29追加）。単一モードにはこの
    // 概念自体が無い（常に広場全体の値を直接編集する）。
    final customSettingsEnabled =
        widget.currentRoom?.customSettingsEnabled ?? false;
    final roomMuted =
        prefs[widget.group.groupId]?.roomNotificationOverrides[widget.roomId] ??
        false;
    final roomReadReceiptsEnabled =
        widget.currentRoom?.readReceiptsEnabledOverride ?? readReceiptsEnabled;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    return PopupMenuButton<_GroupMenuAction>(
      key: _buttonKey,
      icon: isGekiga
          ? const GekigaIconBadge(icon: Icons.menu, size: 36)
          : const Icon(Icons.menu),
      tooltip: '',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) async {
        switch (action) {
          case _GroupMenuAction.profileCard:
            _showProfileCardPopup();
          case _GroupMenuAction.conversationProfileCard:
            ConversationProfileCardDialog.show(
              context,
              currentUserId: widget.currentUser.userId,
              conversationId: widget.group.groupId,
            );
          case _GroupMenuAction.memberList:
            _showMemberListPopup();
          case _GroupMenuAction.createInvite:
            if (!canCreateInvite) return;
            GroupInviteDialog.show(
              context,
              widget.group.groupId,
              widget.group.profileCard,
            );
          case _GroupMenuAction.manageRoles:
            // 単一モード専用（2026-07-29追加）。複数モードのロール管理は
            // サイドバーの「広場自体の設定」（歯車アイコン）から行う。
            if (!canManageRoles) return;
            showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 400,
                    maxHeight: 640,
                  ),
                  child: GroupRoleListPopup(
                    currentUser: widget.currentUser,
                    group: widget.group,
                  ),
                ),
              ),
            );
          case _GroupMenuAction.renameRoom:
            if (!canManageRooms) return;
            final name = await _showRenameRoomDialog(
              context,
              strings,
              vocabulary,
              widget.roomName,
            );
            if (name == null) return;
            await ref
                .read(groupRepositoryProvider)
                .renameRoom(
                  groupId: widget.group.groupId,
                  roomId: widget.roomId,
                  name: name,
                );
          case _GroupMenuAction.deleteRoom:
            if (!canManageRooms) return;
            final confirmed = await _confirmDeleteRoom(
              context,
              strings,
              vocabulary,
            );
            if (!confirmed) return;
            try {
              await ref
                  .read(groupRepositoryProvider)
                  .deleteRoom(
                    groupId: widget.group.groupId,
                    roomId: widget.roomId,
                    requestedBy: widget.currentUser.userId,
                  );
            } on StateError {
              if (context.mounted) {
                showAutoDismissBanner(
                  context,
                  message: strings.roomDeleteLastRoomError,
                );
              }
              return;
            }
            if (!context.mounted) return;
            if (Navigator.of(context).canPop()) {
              // 狭い画面（フルスクリーンpush）: 語らい一覧へ戻すのではなく、
              // 一番上（最古）の寄合を開き直す。最後の1つの寄合は削除
              // できない仕様のため、削除後リストが空になることはない
              // （2026-08-13追加）。
              final remainingRooms = await ref
                  .read(groupRepositoryProvider)
                  .watchRooms(
                    groupId: widget.group.groupId,
                    userId: widget.currentUser.userId,
                  )
                  .first;
              if (!context.mounted) return;
              if (remainingRooms.isNotEmpty) {
                final topRoom = remainingRooms.first;
                ref
                    .read(goRouterProvider)
                    .pushReplacement(
                      '/chat/group',
                      extra: GroupChatArgs(
                        currentUser: widget.currentUser,
                        group: widget.group,
                        roomId: topRoom.roomId,
                        roomName: topRoom.name,
                      ),
                    );
              } else {
                Navigator.of(context).pop();
              }
            }
          // 広い画面（埋め込みペイン）はcanPop()==falseで元々no-op。
          // TalksTab側の既存フォールバック（rooms.first）が自動的に
          // 一番上の寄合を選択するため、追加対応不要。
          case _GroupMenuAction.enableMultipleRooms:
            if (!canManageRooms) return;
            await ref
                .read(groupRepositoryProvider)
                .setRoomsEnabled(groupId: widget.group.groupId, enabled: true);
          case _GroupMenuAction.roomRolePriority:
            if (!canManageRoles) return;
            final regularRoles = widget.roles
                .where((r) => !r.isEveryone)
                .toList();
            final order =
                widget.currentRoom?.rolePriorityOverride ??
                widget.group.rolePriority;
            final orderedRoles = [
              for (final roleId in order)
                ...regularRoles.where((r) => r.roleId == roleId),
              for (final role in regularRoles)
                if (!order.contains(role.roleId)) role,
            ];
            GroupRolePriorityDialog.show(
              context,
              orderedRoles: orderedRoles,
              onSave: (roleIds) => ref
                  .read(groupRepositoryProvider)
                  .setRoomRolePriorityOverride(
                    groupId: widget.group.groupId,
                    roomId: widget.roomId,
                    roleIds: roleIds,
                  ),
              onReset: widget.currentRoom?.rolePriorityOverride == null
                  ? null
                  : () => ref
                        .read(groupRepositoryProvider)
                        .setRoomRolePriorityOverride(
                          groupId: widget.group.groupId,
                          roomId: widget.roomId,
                          roleIds: null,
                        ),
            );
          case _GroupMenuAction.toggleMute:
            // 複数モードでは「この寄合独自の設定」がオンの間だけこの項目が
            // 表示され、その場合はこの寄合専用の値を切り替える（広場全体の
            // 既定値は全体設定ポップアップから編集する、2026-07-29変更）。
            if (widget.group.roomsEnabled) {
              ref
                  .read(conversationPrefsRepositoryProvider)
                  .setRoomNotificationsMuted(
                    userId: widget.currentUser.userId,
                    conversationId: widget.group.groupId,
                    roomId: widget.roomId,
                    muted: !roomMuted,
                  );
            } else {
              ref
                  .read(conversationPrefsRepositoryProvider)
                  .setNotificationsMuted(
                    userId: widget.currentUser.userId,
                    conversationId: widget.group.groupId,
                    muted: !muted,
                  );
            }
          case _GroupMenuAction.toggleReadReceipts:
            // 既読機能のオン/オフはmanageReadReceipts権限を持つメンバーのみ
            // 操作可能（firestore.rulesで強制、メニュー項目自体もそれ以外は
            // enabled: falseにしている）。オフにする場合のみ、確定前に
            // 既読履歴が消える旨を警告する。複数モードでは「この寄合独自の
            // 設定」がオンの間だけこの項目が表示され、この寄合専用の値を
            // 切り替える（2026-07-29変更）。
            if (!canManageReadReceipts) return;
            if (widget.group.roomsEnabled) {
              if (roomReadReceiptsEnabled) {
                final confirmed = await confirmDisableReadReceipts(
                  context,
                  strings,
                );
                if (!confirmed) return;
              }
              ref
                  .read(groupRepositoryProvider)
                  .setRoomReadReceiptsEnabledOverride(
                    groupId: widget.group.groupId,
                    roomId: widget.roomId,
                    enabled: !roomReadReceiptsEnabled,
                  );
            } else {
              if (readReceiptsEnabled) {
                final confirmed = await confirmDisableReadReceipts(
                  context,
                  strings,
                );
                if (!confirmed) return;
              }
              ref
                  .read(groupRepositoryProvider)
                  .setReadReceiptsEnabled(
                    groupId: widget.group.groupId,
                    enabled: !readReceiptsEnabled,
                    userId: widget.currentUser.userId,
                  );
            }
          case _GroupMenuAction.leave:
            GroupLeaveDialog.show(
              context,
              groupId: widget.group.groupId,
              userId: widget.currentUser.userId,
            );
          case _GroupMenuAction.deleteGroup:
            if (!isOwner) return;
            GroupDeleteDialog.show(
              context,
              groupId: widget.group.groupId,
              userId: widget.currentUser.userId,
            );
        }
      },
      itemBuilder: (context) => [
        // 単一モード（サイドバー・全体設定ポップアップが無い）の間だけ、
        // 本来は全体設定に置くべき項目もここへ集約する例外扱い
        // （2026-07-29変更。複数モードではサイドバーの「広場自体の設定」
        // 歯車アイコン＝`GroupSettingsPopup`にこれらを移設した）。
        if (!widget.group.roomsEnabled) ...[
          PopupMenuItem(
            value: _GroupMenuAction.profileCard,
            child: Text(strings.groupMenuProfileCard),
          ),
          if (widget.currentUser.profileCards.length > 1)
            PopupMenuItem(
              value: _GroupMenuAction.conversationProfileCard,
              child: Text(strings.conversationProfileCardMenuLabel),
            ),
          PopupMenuItem(
            value: _GroupMenuAction.memberList,
            child: Text(strings.groupMenuMemberList),
          ),
          PopupMenuItem(
            value: _GroupMenuAction.createInvite,
            enabled: canCreateInvite,
            child: Text(strings.groupMenuCreateInvite),
          ),
          PopupMenuItem(
            value: _GroupMenuAction.manageRoles,
            enabled: canManageRoles,
            child: Text(strings.groupMenuManageRoles),
          ),
          PopupMenuItem(
            value: _GroupMenuAction.deleteGroup,
            enabled: isOwner,
            child: Text(
              strings.groupDeleteMenuLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        PopupMenuItem(
          value: _GroupMenuAction.renameRoom,
          enabled: canManageRooms,
          child: Text(strings.roomRenameLabel(vocabulary.textChannel)),
        ),
        // 寄合一覧サイドバーのごみ箱アイコンの代わり（2026-07-30変更）。
        // 最後の1つの寄合は選べても実際には削除できず、リポジトリが
        // StateErrorを投げてSnackBarで案内する（`onSelected`参照）。
        PopupMenuItem(
          value: _GroupMenuAction.deleteRoom,
          enabled: canManageRooms,
          child: Text(
            strings.roomMenuDeleteLabel(vocabulary.textChannel),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        // 単一モードの間だけ「寄合を複数扱う」を出す。複数モードへの切り替えは
        // 一方向のみ（2026-07-29追加、`Group.roomsEnabled`参照）。
        if (!widget.group.roomsEnabled)
          PopupMenuItem(
            value: _GroupMenuAction.enableMultipleRooms,
            enabled: canManageRooms,
            child: Text(strings.groupMenuEnableMultipleRooms),
          ),
        if (widget.group.roomsEnabled) ...[
          // 複数モードでは、通知・既読・ロール優先順位の寄合固有設定は
          // 「この寄合独自の設定」がオンの間だけ表示する（2026-07-29変更、
          // 広場全体の既定値は`GroupSettingsPopup`から編集する）。
          if (customSettingsEnabled) ...[
            PopupMenuItem(
              value: _GroupMenuAction.roomRolePriority,
              enabled: canManageRoles,
              child: Text(strings.groupRoomRolePriorityMenuItem),
            ),
            PopupMenuItem(
              value: _GroupMenuAction.toggleMute,
              child: Text(
                roomMuted
                    ? strings.conversationUnmute
                    : strings.conversationMute,
              ),
            ),
            PopupMenuItem(
              value: _GroupMenuAction.toggleReadReceipts,
              enabled: canManageReadReceipts,
              child: Text(
                roomReadReceiptsEnabled
                    ? strings.conversationReadReceiptsDisable
                    : strings.conversationReadReceiptsEnable,
              ),
            ),
          ],
          const PopupMenuDivider(),
          PopupMenuItem<_GroupMenuAction>(
            enabled: canManageRooms,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: customSettingsEnabled,
              title: Text(strings.groupRoomCustomSettingsLabel),
              subtitle: Text(
                strings.groupRoomCustomSettingsHint,
                style: const TextStyle(fontSize: 11),
              ),
              onChanged: !canManageRooms
                  ? null
                  : (value) => ref
                        .read(groupRepositoryProvider)
                        .setRoomCustomSettingsEnabled(
                          groupId: widget.group.groupId,
                          roomId: widget.roomId,
                          enabled: value,
                        ),
            ),
          ),
        ] else ...[
          PopupMenuItem(
            value: _GroupMenuAction.toggleMute,
            child: Text(
              muted ? strings.conversationUnmute : strings.conversationMute,
            ),
          ),
          // 既読機能のオン/オフはmanageReadReceipts権限を持つメンバーのみ操作
          // 可能。それ以外には現在の状態を示すラベルとして表示するが、操作は
          // できない（leaveがisOwnerで無効化されているのと同じ考え方）。
          PopupMenuItem(
            value: _GroupMenuAction.toggleReadReceipts,
            enabled: canManageReadReceipts,
            child: Text(
              readReceiptsEnabled
                  ? strings.conversationReadReceiptsDisable
                  : strings.conversationReadReceiptsEnable,
            ),
          ),
        ],
        PopupMenuItem(
          value: _GroupMenuAction.leave,
          enabled: !isOwner,
          child: Text(strings.groupMenuLeave),
        ),
      ],
    );
  }
}
