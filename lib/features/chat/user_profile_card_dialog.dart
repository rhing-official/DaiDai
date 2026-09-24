import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/friend_request.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/friend_request_error.dart';
import '../../widgets/profile_card_composer.dart';
import '../../widgets/profile_card_view.dart';
import '../../widgets/sns_link_list.dart';
import 'talks_tab.dart' show kTalksSplitBreakpoint;

/// 広場（グループ）・一対（DM）どちらのメッセージ画面・メンバー一覧からも、
/// 相手のプロフィールカード（適用中の工房カード）を見られるダイアログ。
/// 友達でなければその場で友達申請を送れる（相手から既に申請が届いていれば、
/// 送信するとそのまま承認扱いになる。[FriendRepository.sendRequest]の
/// 既存の挙動）。友達の場合は右上に一対へのジャンプボタンを出す
/// （広場のメンバーから開いた場合はその相手との一対を新規作成/取得して遷移、
/// 一対から開いた場合は今開いている一対と同じ相手のためそのまま遷移するだけ）。
class UserProfileCardDialog extends ConsumerStatefulWidget {
  const UserProfileCardDialog({
    required this.currentUser,
    required this.user,
    this.conversationId,
    this.canTransferOwnership = false,
    this.onTransferOwnership,
    super.key,
  });

  final AppUser currentUser;
  final AppUser user;

  /// このダイアログを開いた会話（一対のdmId・広場のgroupId）。会話ごとに
  /// 使うプロフィールカード（2026-07-29追加、`AppUser.conversationProfileCardId`）
  /// を反映した表示にするために使う。nullなら標準のカードで表示する
  /// （会話コンテキストが無い場所から開いた場合）。
  final String? conversationId;

  /// 広場のメンバー一覧から開かれ、かつ開いた側が長かつ相手が自分以外の場合に
  /// true。trueの場合のみ「長を譲渡」ボタンを表示する（2026-07-29、メンバー
  /// 一覧に直接ボタンを置くと誤操作の危険が高いためこちらに統合した）。
  final bool canTransferOwnership;

  /// [canTransferOwnership]がtrueの間だけ使う、確認ダイアログ込みの譲渡処理
  /// （呼び出し元の`group_member_list_screen.dart`の`_confirmTransferOwnership`
  /// をそのまま渡す）。
  final VoidCallback? onTransferOwnership;

  static Future<void> show(
    BuildContext context, {
    required AppUser currentUser,
    required AppUser user,
    String? conversationId,
    bool canTransferOwnership = false,
    VoidCallback? onTransferOwnership,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => UserProfileCardDialog(
        currentUser: currentUser,
        user: user,
        conversationId: conversationId,
        canTransferOwnership: canTransferOwnership,
        onTransferOwnership: onTransferOwnership,
      ),
    );
  }

  @override
  ConsumerState<UserProfileCardDialog> createState() =>
      _UserProfileCardDialogState();
}

class _UserProfileCardDialogState extends ConsumerState<UserProfileCardDialog> {
  late Future<({bool isFriend, FriendRequest? request})> _statusFuture;
  bool _sending = false;

  /// 申請に添える任意メッセージ（技術仕様書8.3レイヤー2、2026-09-07追加）。
  /// 2026-09-24、見た目をチャット画面のコンポーザーに寄せる形に変更
  /// （`ProfileCardComposer`）。「使うプロフィールカード」選択欄は
  /// このダイアログから削除し、常に標準カードが使われるようにした。
  final _messageController = TextEditingController();

  String? _errorMessage;

  bool get _isSelf => widget.currentUser.userId == widget.user.userId;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _statusFuture = _fetchStatus();
  }

  /// 「友達か」は[FriendRequest.status]ではなく[FriendRepository.isFriend]
  /// （実際のfriendsサブコレクション）を根拠にする。絶縁等で友達関係が
  /// 解消された後も申請ドキュメントがaccepted状態のまま残っているケースが
  /// あり、statusだけを見ると友達解消後も「友達です」と表示され続けてしまう
  /// バグがあったため。申請ドキュメントは、まだ友達でない場合の
  /// 申請中/未申請の判定にのみ使う。
  Future<({bool isFriend, FriendRequest? request})> _fetchStatus() async {
    final repository = ref.read(friendRepositoryProvider);
    final results = await Future.wait([
      repository.isFriend(
        userId: widget.currentUser.userId,
        otherUserId: widget.user.userId,
      ),
      repository.getRequest(widget.currentUser.userId, widget.user.userId),
    ]);
    return (
      isFriend: results[0] as bool,
      request: results[1] as FriendRequest?,
    );
  }

  Future<void> _sendRequest() async {
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      final message = _messageController.text.trim();
      await ref
          .read(friendRepositoryProvider)
          .sendRequest(
            from: widget.currentUser,
            to: widget.user,
            message: message.isEmpty ? null : message,
          );
      if (!mounted) return;
      setState(() => _statusFuture = _fetchStatus());
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = friendRequestErrorMessage(
          e,
          ref.read(appStringsProvider),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _jumpToDm() async {
    final dmRepository = ref.read(directMessageRepositoryProvider);
    final dm = await dmRepository.getOrCreateDirectMessage(
      widget.currentUser,
      widget.user,
    );
    if (!mounted) return;
    final isSplit = MediaQuery.sizeOf(context).width >= kTalksSplitBreakpoint;
    if (isSplit) {
      Navigator.of(context).pop();
      // 左右分割表示ではTalksTabが一覧＋チャットを自前のStateで表示している
      // ため、ここでルートをpushすると全画面ルートがサイドバーごと覆って
      // しまい、一覧から開いた時と見え方が変わってしまう（2026-07-29修正）。
      // TalksTab側にこの一対を選ばせ、home（'/'）に戻るだけにする。
      ref.read(goRouterProvider).go('/');
      ref.read(pendingDmSelectionProvider.notifier).set(dm);
      return;
    }
    // この一対で最も古い（`createdAt`が最小の）寄合を開く（2026-09-14変更、
    // 以前は`defaultRoomId`を直接参照していた。`talks_tab.dart`の
    // `_openDirectMessage`と同じ考え方）。
    final rooms = await dmRepository
        .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
        .first;
    if (!mounted || rooms.isEmpty) return;
    Navigator.of(context).pop();
    ref
        .read(goRouterProvider)
        .push(
          '/chat/dm',
          extra: DmChatArgs(
            currentUser: widget.currentUser,
            dm: dm,
            roomId: rooms.first.roomId,
            roomName: rooms.first.name,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final nickname = user.effectiveNicknameFor(widget.conversationId);
    final name = (nickname?.text.isNotEmpty ?? false)
        ? nickname!.text
        : '@${user.rhingSeed}';
    final icon = user.effectiveIconFor(widget.conversationId);
    final background = user.effectiveBackgroundImageFor(widget.conversationId);
    final statusMessage = user
        .effectiveStatusMessageFor(widget.conversationId)
        ?.text;
    final snsLinks = user.effectiveSnsLinksFor(widget.conversationId);

    // 身だしなみ・工房で作るカード（ProfileCardView）と全く同じ比率
    // （height = width * 1.25）で表示する。以前は固定height:360を使っており
    // 工房での見え方（切り取られ方）と食い違っていた（2026-07-29修正）。
    // 画面の幅・高さ両方から動的に幅を決め、どちらの制約でも
    // ビューポートをはみ出さないようにする（縦横比は常に1.25を維持）。
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeightBudget = screenSize.height * 0.6;
    final cardWidth = (screenSize.width - 80)
        .clamp(240.0, 480.0)
        .clamp(0.0, maxHeightBudget / 1.25);
    final cardHeight = cardWidth * 1.25;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      // 以前はカード＋フッター全体を1つの連続したClipRRect(circular(30))で
      // クリップしており、写真カード（4:5固定）とその下のピッカー・
      // メッセージ欄・ボタンが隙間なく同居して「1つの巨大な縦長カード」に
      // 見えてしまっていた（2026-09-24修正）。カード自体（ProfileCardView）
      // に独立した角丸を持たせ、SNSリンク・フッターとは視覚的に区切る。
      // ダイアログの背景色自体はこのDialog標準の色をそのまま使う。
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: cardWidth,
          maxHeight: screenSize.height * 0.9,
        ),
        // カード下の要素が長くなる場合でも画面外に切れず、その場で
        // スクロールできるようにする（ビューポート溢れの保険）。
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProfileCardView(
                      width: cardWidth,
                      height: cardHeight,
                      icon: icon,
                      background: background,
                      nickname: name,
                      statusMessage: statusMessage,
                      // SNSリンクはカード内の非タップ可能テキストとしては
                      // 表示しない。カードの下にタップ可能な別要素
                      // （SnsLinkList）として表示する（2026-09-24変更）。
                      snsLinks: const [],
                    ),
                    if (!_isSelf)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FutureBuilder<
                              ({bool isFriend, FriendRequest? request})
                            >(
                              future: _statusFuture,
                              builder: (context, snapshot) {
                                if (snapshot.data?.isFriend != true) {
                                  return const SizedBox.shrink();
                                }
                                return Material(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.send_outlined,
                                      color: Colors.white,
                                    ),
                                    iconSize: 30,
                                    onPressed: _jumpToDm,
                                  ),
                                );
                              },
                            ),
                            // 長の譲渡はメンバー一覧から開いた場合のみ表示する
                            // （2026-07-29、一対へのジャンプボタンの右横に配置。
                            // プライマリーカラーで目立たせる）。
                            if (widget.canTransferOwnership) ...[
                              const SizedBox(width: 8),
                              Material(
                                color: colorScheme.primary,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.workspace_premium_outlined,
                                    color: colorScheme.onPrimary,
                                  ),
                                  iconSize: 30,
                                  onPressed: widget.onTransferOwnership,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (snsLinks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SnsLinkList(links: snsLinks),
                ),
              ],
              if (!_isSelf) ...[
                const SizedBox(height: 4),
                _friendFooter(strings),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 友達申請の送信・承認が必要な場合のみ、カードの下に領域を追加する。
  /// 既に友達（ジャンプボタンの表示自体で伝わるため文言は出さない）・
  /// 自分自身の場合はフッター自体を出さず、工房で作ったカードそのままの
  /// 見た目にする（2026-07-29変更）。
  ///
  /// 中身は3状態: (a)未送信、(b)自分から送信済み・返答待ち（欄は消さず
  /// グレーアウト）、(c)相手から届いている（送信すると承認扱いになる）。
  /// （b）(c)の判定に使う`isFriend`のロジック自体は変更していない
  /// （2026-09-24、状態(a)(b)(c)の見た目を`ProfileCardComposer`に統一）。
  Widget _friendFooter(Strings strings) {
    return FutureBuilder<({bool isFriend, FriendRequest? request})>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.data?.isFriend ?? false) {
          return const SizedBox.shrink();
        }

        final request = snapshot.data?.request;
        final isPendingFromMe =
            request?.status == FriendRequestStatus.pending &&
            request!.fromUserId == widget.currentUser.userId;
        final isPendingFromOther =
            request?.status == FriendRequestStatus.pending && !isPendingFromMe;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isPendingFromOther) ...[
                Text(
                  strings.userProfileCardAcceptNotice,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
              ],
              ProfileCardComposer(
                controller: _messageController,
                // 送信済み・返答待ちの間は欄自体は消さずグレーアウトする
                // （消すとUXが分かりにくいというユーザー指摘を踏まえた挙動）。
                enabled: !_sending && !isPendingFromMe,
                hintText: isPendingFromMe
                    ? strings.userProfileCardComposerLockedHint
                    : strings.userProfileCardComposerHint,
                sending: _sending,
                onSend: isPendingFromMe ? null : _sendRequest,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        );
      },
    );
  }
}
