import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/friend_request.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/open_conversation.dart';
import '../../utils/friend_request_error.dart';
import '../../widgets/profile_card_composer.dart';
import '../../widgets/user_profile_card_view.dart';
import '../../widgets/sns_link_list.dart';

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

  /// 相手が友達だと判明しているか（読み込み前はfalse）。URLの無い友達のカードを
  /// 「カードだけ」の枠なし表示にするために使う（2026-10-31）。
  bool _isFriendKnown = false;
  bool _statusKnown = false;

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
    _watchFriendStatus();
  }

  void _watchFriendStatus() {
    _statusFuture.then((status) {
      if (!mounted) return;
      setState(() {
        _isFriendKnown = status.isFriend;
        _statusKnown = true;
      });
    });
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
      _watchFriendStatus();
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
    Navigator.of(context).pop();
    // 左右分割表示ではTalksTabが一覧＋チャットを自前のStateで表示しているため、
    // ここでルートをpushすると全画面ルートがサイドバーごと覆ってしまう
    // （2026-07-29修正）。狭い画面でも設定した語らいレイアウトどおりに開くよう、
    // どちらもTalksTabへ選択を渡す（2026-10-11変更）。
    await openDmInTalks(ref, dm);
  }

  /// 自分のカードの右上のボタン。身だしなみタブの仕立てへ移動する（2026-10-31）。
  void _jumpToWorkshop() {
    Navigator.of(context).pop();
    ref.read(homeSelectedTabProvider.notifier).set(kProfileTabIndex);
    ref.read(openWorkshopRequestProvider.notifier).request();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.user;

    // 身だしなみ・工房で作るカード（ProfileCardView）と全く同じ比率
    // （height = width * 1.25）で表示する。以前は固定height:360を使っており
    // 工房での見え方（切り取られ方）と食い違っていた（2026-07-29修正）。
    // 画面の幅・高さ両方から動的に幅を決め、どちらの制約でも
    // ビューポートをはみ出さないようにする（縦横比は常に1.25を維持）。
    final screenSize = MediaQuery.sizeOf(context);
    // カードの周りには余白を作らない（2026-10-31、URLの有無に関わらず）。ダイアログ
    // 自体は透明にして、カードを角丸のまま見せる。URL・友達申請の入力欄は、カードの
    // 下に別の角丸のパネルとして続ける（出す内容がある時だけ）。
    final hasBelow = !_isSelf && _statusKnown && !_isFriendKnown;
    // カードは、実際に渡った幅に対して必ず4:5にする。
    final maxHeightBudget = screenSize.height * 0.6;
    final cardWidth = (screenSize.width - 80)
        .clamp(240.0, 480.0)
        .clamp(0.0, maxHeightBudget / 1.25);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: cardWidth,
          maxHeight: screenSize.height * 0.9,
        ),
        // カード下の要素が長くなる場合でも画面外に切れず、その場で
        // スクロールできるようにする（ビューポート溢れの保険）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // カードの領域は、実際に渡った幅に対して常に4:5にし、四隅を角丸で
              // 切る（2026-10-31）。固定の幅・高さを渡すと、実際の制約とずれた時に
              // 中身が縮んで四隅が直角に見える。
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 0.8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // SNSリンクはカード内の非タップ可能テキストとしては
                      // 表示しない。カードの下にタップ可能な別要素
                      // （SnsLinkList）として表示する（2026-09-24変更）。
                      LayoutBuilder(
                        builder: (context, box) => UserProfileCardView(
                          user: user,
                          conversationId: widget.conversationId,
                          width: box.maxWidth,
                          height: box.maxHeight,
                          // URLはカード内にアイコン付きで出し、タップで開く（2026-10-31）。
                          onOpenSnsLink: (link) => openSnsLink(link.url),
                        ),
                      ),
                      // 自分のカードには、他のユーザーの「一対へ」の飛行機の代わりに、
                      // 身だしなみのアイコン（仕立てへジャンプ）を出す。
                      if (_isSelf)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(
                                Icons.face_outlined,
                                color: Colors.white,
                              ),
                              iconSize: 30,
                              onPressed: _jumpToWorkshop,
                            ),
                          ),
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
              ),
              if (hasBelow) ...[
                const SizedBox(height: 8),
                // 友達申請の入力欄は、周りに枠・パネルを付けず、カードの下に直接出す。
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
                // 「任意」「100文字以内」は箇条書きで、入力欄の枠の中に出す。
                notes: isPendingFromMe
                    ? const []
                    : [
                        strings.userProfileCardComposerOptionalNote,
                        strings.userProfileCardComposerLimitNote,
                      ],
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
