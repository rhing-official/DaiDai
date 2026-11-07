import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../models/friend_request.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/contact_alias_providers.dart';
import '../../providers/chat_navigation_providers.dart'
    show pendingDmSelectionProvider, ViewedDm;
import '../../providers/home_shell_providers.dart';
import '../../providers/talks_resume_provider.dart';
import '../../router/app_router.dart' show isFullscreenChatOpen;
import '../../router/back_stack.dart' show backStackControllerProvider;
import '../../router/app_router.dart' show goRouterProvider;
import '../../providers/last_opened_room_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/contact_alias.dart';
import '../../widgets/media_preview_frame.dart'
    show GekigaStraightMonochromeBox;
import '../../widgets/glass/glass_surface.dart';
import 'contact_alias_dialog.dart';
import '../../providers/repository_providers.dart';
import '../../utils/friend_request_error.dart';
import '../../widgets/profile_card_composer.dart';
import '../../widgets/user_profile_card_view.dart';
import '../../widgets/sns_link_list.dart';
import '../../widgets/app_dialog.dart';

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

  /// このダイアログを開いた会話（一対のdmId・広場のgroupId）。会話毎に
  /// 使うプロフィールカード（2026-07-29追加、`AppUser.conversationProfileCardId`）
  /// を反映した表示にする為に使う。nullなら標準のカードで表示する
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
    return showAppDialog<void>(
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
  /// 「カードだけ」の枠なし表示にする為に使う（2026-10-31）。
  bool _isFriendKnown = false;
  bool _statusKnown = false;

  /// 申請に添える任意メッセージ（技術仕様書8.3レイヤー2、2026-09-07追加）。
  /// 2026-09-24、見た目をチャット画面のコンポーザーに寄せる形に変更
  /// （`ProfileCardComposer`）。「使うプロフィールカード」選択欄は
  /// このダイアログから削除し、常に標準カードが使われるようにした。
  final _messageController = TextEditingController();

  String? _errorMessage;

  bool get _isSelf => widget.currentUser.userId == widget.user.userId;

  /// 相手の呼び名を自分の画面だけで指定・取り消す（2026-11-06）。
  Future<void> _editAlias() async {
    final strings = ref.read(appStringsProvider);
    final ui = ref.read(appUiStyleProvider);
    final aliases = ref.read(myContactAliasesProvider).value;
    final result = await promptContactAlias(
      context,
      strings,
      current: aliasOf(aliases, widget.user.userId),
      original: widget.user.effectiveNicknameFor(widget.conversationId)?.text,
      isGekiga: ui == AppUiStyle.gekiga,
      isGlass: ui == AppUiStyle.glass,
    );
    if (result == null) return;
    final repository = ref.read(contactAliasRepositoryProvider);
    if (result.isEmpty) {
      await repository.clearAlias(
        userId: widget.currentUser.userId,
        targetUserId: widget.user.userId,
      );
    } else {
      await repository.setAlias(
        userId: widget.currentUser.userId,
        targetUserId: widget.user.userId,
        alias: result,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _hoveredRoom.dispose();
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
  /// バグがあった為。申請ドキュメントは、まだ友達でない場合の
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

  final GlobalKey _dmJumpKey = GlobalKey();
  final Map<String, GlobalKey> _roomItemKeys = {};
  final ValueNotifier<String?> _hoveredRoom = ValueNotifier(null);
  bool _roomMenuOpen = false;
  bool _jumping = false;
  bool _prefetchStarted = false;
  DirectMessage? _cachedDm;
  List<DmRoom>? _cachedRooms;

  /// ボタンを押した瞬間にプルダウンを開けるよう、友達の一対と寄合を先に読んでおく
  /// （読み取りだけ。一対がまだ無ければ何もしない）。
  Future<void> _prefetchDm() async {
    if (_prefetchStarted) return;
    _prefetchStarted = true;
    try {
      final repo = ref.read(directMessageRepositoryProvider);
      final dm = await repo.getDirectMessage(
        DirectMessage.idFor(widget.currentUser.userId, widget.user.userId),
      );
      if (dm == null || !dm.roomsEnabled) return;
      final rooms = await repo
          .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
          .first;
      _cachedDm = dm;
      _cachedRooms = rooms;
    } catch (_) {
      // 先読みは任意。失敗したら押した時に読む。
    }
  }

  String? _roomAt(Offset global) {
    for (final e in _roomItemKeys.entries) {
      final box = e.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if ((box.localToGlobal(Offset.zero) & box.size).contains(global)) {
        return e.key;
      }
    }
    return null;
  }

  /// 寄合機能がオンの一対では、飛行機ボタンの下にプルダウンを出し、ジャンプ先の寄合を選ばせる
  /// （2026-11-07）。UIスタイルの面（劇画=黒の箱、ガラス=すりガラス、版画=太枠、フラット=枠付き）で描く。
  Future<String?> _pickDmRoom(List<DmRoom> rooms) async {
    if (!mounted || rooms.length < 2) {
      return rooms.isEmpty ? null : rooms.first.roomId;
    }
    final box = _dmJumpKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    if (box == null) return null;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final ui = ref.read(appUiStyleProvider);
    final theme = Theme.of(context);
    _roomItemKeys
      ..clear()
      ..addEntries(rooms.map((r) => MapEntry(r.roomId, GlobalKey())));
    _roomMenuOpen = true;
    _hoveredRoom.value = null;
    final isGekiga = ui == AppUiStyle.gekiga;
    final fg = isGekiga ? GekigaColors.onPanel : theme.colorScheme.onSurface;
    final picked = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      // テーマ（版画の太枠など）が外側にも枠を描いて二重になるのを避ける。
      shape: const RoundedRectangleBorder(),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Builder(
            builder: (menuContext) {
              final list = ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final room in rooms)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              Navigator.of(menuContext).pop(room.roomId),
                          child: ValueListenableBuilder<String?>(
                            valueListenable: _hoveredRoom,
                            builder: (context, hovered, child) => ColoredBox(
                              key: _roomItemKeys[room.roomId],
                              color: hovered == room.roomId
                                  ? fg.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              child: child,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                '# ${room.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: fg),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
              final radius = BorderRadius.circular(12);
              switch (ui) {
                case AppUiStyle.gekiga:
                  return GekigaStraightMonochromeBox(isMe: false, child: list);
                case AppUiStyle.glass:
                  return GlassSurface(
                    variant: GlassVariant.floating,
                    borderRadius: radius,
                    child: ClipRRect(borderRadius: radius, child: list),
                  );
                case AppUiStyle.block:
                  return blockMaterialBox(
                    menuContext,
                    color: theme.colorScheme.surface,
                    child: list,
                  );
                case AppUiStyle.flat:
                  return Material(
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: radius,
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: list,
                  );
              }
            },
          ),
        ),
      ],
    );
    _roomMenuOpen = false;
    _hoveredRoom.value = null;
    return picked;
  }

  Future<void> _jumpToDm() async {
    if (_jumping) return;
    _jumping = true;
    try {
      await _jumpToDmImpl();
    } finally {
      _jumping = false;
    }
  }

  Future<void> _jumpToDmImpl() async {
    final dmRepository = ref.read(directMessageRepositoryProvider);
    // 先読み済みなら、待たずにその場でプルダウンを開く（押したまま選べるように）。
    final DirectMessage dm =
        _cachedDm ??
        await dmRepository.getOrCreateDirectMessage(
          widget.currentUser,
          widget.user,
        );
    if (!mounted) return;
    String? roomId;
    if (dm.roomsEnabled) {
      final rooms =
          _cachedRooms ??
          await dmRepository
              .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
              .first;
      if (!mounted) return;
      roomId = await _pickDmRoom(rooms);
      if (!mounted || roomId == null) return;
      await ref
          .read(lastOpenedRoomProvider.notifier)
          .setLastRoom(ViewedDm(dm.dmId), roomId);
      if (!mounted) return;
    }
    final router = ref.read(goRouterProvider);
    final backStack = ref.read(backStackControllerProvider);
    final pending = ref.read(pendingDmSelectionProvider.notifier);
    final tab = ref.read(homeSelectedTabProvider.notifier);
    // 以前は`openDmInTalks`の`go('/')`でホームへ戻していたが、`go('/')`は戻る操作用の
    // 透明ルートを消して履歴を巻き戻し、語らいの選択（会話・寄合）を外してしまう
    // （2026-11-07修正）。ここでは`go('/')`を使わない。スマホで全画面のメッセージ画面が
    // 開いている時だけ、そのルートを閉じる。
    final isFullscreenChat = isFullscreenChatOpen(router);
    if (isFullscreenChat) {
      if (!backStack.closeTopOverlay()) Navigator.of(context).pop();
      backStack.allowNextChatExit();
      if (router.canPop()) {
        router.pop();
      } else {
        backStack.cancelAllowChatExit();
      }
    } else {
      Navigator.of(context).pop();
    }
    // 左右分割表示では語らいタブの中で会話を選び直すだけ。全画面のルートを閉じた直後は、
    // 描画が落ち着いてから開く（閉じる動きと開く動きが重ならないように）。
    void open() {
      tab.set(kTalksTabIndex);
      pending.set(dm);
    }

    if (isFullscreenChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }

  /// 自分のカードの右上のボタン。身だしなみタブの仕立てへ移動する（2026-10-31）。
  /// スマホではメッセージ画面が全画面のルートとして重なっている為、ホームへ戻してから
  /// タブを切り替える（戻さないと、裏で身だしなみが開くだけで画面が変わらなかった、
  /// 2026-11-06修正）。ダイアログを閉じた後は`ref`が使えなくなる可能性があるので、
  /// 使うものは閉じる前に取っておく。タブの切り替えは、画面遷移の設定どおりの現れ方にする。
  void _jumpToWorkshop() {
    final router = ref.read(goRouterProvider);
    final backStack = ref.read(backStackControllerProvider);
    final tab = ref.read(homeSelectedTabProvider.notifier);
    final appear = ref.read(homeTabAppearRequestProvider.notifier);
    final workshop = ref.read(openWorkshopRequestProvider.notifier);
    final resume = ref.read(talksResumeProvider.notifier);
    final openChat = ref.read(openChatProvider);
    // スマホでは、メッセージ画面が全画面のルート（`/chat/*`）としてホームの上に重なっている。
    // その下のホームで身だしなみへ切り替えても見えない為、そのルートだけを閉じる。閉じる前に
    // 会話を覚えておき、語らいへ戻った時に開き直す（作業をすぐ再開できるように）。
    // `go('/')`は使わない: 戻る操作用の透明ルートが消えて、履歴が巻き戻り、語らいの
    // 選択（会話・寄合）が戻ってしまう（2026-11-06）。コンピューター・タブレットは、
    // メッセージ画面が語らいのタブの中にある為、ルートは閉じず、タブを切り替えるだけ。
    // `currentConfiguration.uri`は`push`したルートを反映しない（go_routerの仕様）為、
    // 一番上のマッチを見る`isFullscreenChatOpen`で判定する。
    final isFullscreenChat = isFullscreenChatOpen(router);
    // 開いていた会話は、画面の向き・レイアウトによらず保存する（語らいへ戻った時に、状態が
    // 残っていなければ開き直す。横画面は寄合のメッセージ画面まで、縦画面は寄合一覧まで）。
    if (openChat != null) {
      resume.save(openChat);
      if (kDebugMode) {
        debugPrint(
          '[RESUME] saved ${openChat.conversationId} room=${openChat.roomId} '
          'fullscreen=$isFullscreenChat',
        );
      }
    } else if (kDebugMode) {
      debugPrint('[RESUME] not saved: no open chat recorded');
    }
    if (isFullscreenChat) {
      // ダイアログは、閉じる登録を即座に外せる経路で閉じる（`Navigator.pop`だと登録が
      // 残り、`/chat/*`の終了を「ダイアログを閉じた」扱いで中止してしまう）。
      if (!backStack.closeTopOverlay()) Navigator.of(context).pop();
      backStack.allowNextChatExit();
      if (router.canPop()) {
        router.pop();
      } else {
        backStack.cancelAllowChatExit();
      }
    } else {
      Navigator.of(context).pop();
    }
    // ルートの組み直しが落ち着いてから切り替える（身だしなみタブが先に依頼を受け取れるように）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appear.request();
      tab.set(kProfileTabIndex);
      workshop.request();
    });
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
        // スクロール出来るようにする（ビューポート溢れの保険）。
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
                          copyRhingSeed: true,
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
                              Material(
                                color: Colors.black.withValues(alpha: 0.35),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: ref
                                      .watch(appStringsProvider)
                                      .contactAliasAction,
                                  icon: const Icon(
                                    Icons.badge_outlined,
                                    color: Colors.white,
                                  ),
                                  iconSize: 30,
                                  onPressed: _editAlias,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FutureBuilder<
                                ({bool isFriend, FriendRequest? request})
                              >(
                                future: _statusFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.data?.isFriend != true) {
                                    return const SizedBox.shrink();
                                  }
                                  _prefetchDm();
                                  return Material(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    shape: const CircleBorder(),
                                    child: Listener(
                                      onPointerDown: (e) {
                                        if (e.kind == PointerDeviceKind.mouse &&
                                            e.buttons != kPrimaryMouseButton) {
                                          return;
                                        }
                                        _jumpToDm();
                                      },
                                      onPointerMove: (e) {
                                        if (_roomMenuOpen) {
                                          _hoveredRoom.value = _roomAt(
                                            e.position,
                                          );
                                        }
                                      },
                                      onPointerUp: (e) {
                                        if (!_roomMenuOpen) return;
                                        final room = _roomAt(e.position);
                                        if (room != null) {
                                          Navigator.of(context).pop(room);
                                        }
                                      },
                                      child: IconButton(
                                        key: _dmJumpKey,
                                        icon: const Icon(
                                          Icons.send_outlined,
                                          color: Colors.white,
                                        ),
                                        iconSize: 30,
                                        onPressed: () {},
                                      ),
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
