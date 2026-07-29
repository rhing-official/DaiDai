import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/chat_layout_style.dart';
import '../../models/message.dart';
import '../../models/message_time_format.dart';
import '../../models/send_key_mode.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../theme/app_theme_extras.dart';
import '../../utils/link_detection.dart';
import '../../utils/message_time.dart';
import '../../widgets/link_preview_card.dart';
import '../../widgets/linkified_text.dart';

/// 劇画スタイル（[AppUiStyle.gekiga]）のメッセージ画面全体の固定背景色。
/// アクセントカラーとは独立の、このスタイル専用の色（2026-07-29追加）。
const _kGekigaBackground = Color(0xFFC1272D);

/// 一対・広場（お部屋）どちらの会話でも使える汎用チャット画面。
/// メッセージの取得・送信方法は呼び出し元がstream/callbackとして渡す。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.title,
    required this.currentUserId,
    required this.isDm,
    this.conversationId,
    required this.messagesStream,
    required this.onSend,
    this.onCallPressed,
    this.onVideoCallPressed,
    this.extraActions,
    this.readReceiptsEnabled = true,
    this.onMarkRead,
    this.banner,
    this.onSenderTap,
    this.senderNameColorResolver,
    this.onHideMessages,
    this.onEditMessage,
    this.onUnsendMessage,
    this.onSetReaction,
    this.onDeclineAccountDeletionNotice,
    this.onDeleteAfterAccountDeletion,
    this.onFetchMessagesAround,
    super.key,
  });

  final String title;
  final String currentUserId;

  /// 一対（1対1）か広場（グループ）か。[ChatLayoutStyle.sideBySide]で、
  /// 相手のアイコン・呼び名を表示するかどうかの判定に使う。
  final bool isDm;

  /// この会話（一対のdmId・広場のgroupId）。会話ごとに使うプロフィールカード
  /// （2026-07-29追加、`AppUser.conversationProfileCardId`）を反映して
  /// 送信者名・アイコンを表示するために使う。nullなら標準のカードで表示する。
  final String? conversationId;

  final Stream<List<Message>> messagesStream;
  final Future<void> Function(String content, {bool silent, Message? replyTo}) onSend;

  /// 送信済みテキストメッセージの本文を編集する。nullなら編集機能自体を
  /// 提供しない（メニューに「編集」項目を出さない）。
  final Future<void> Function(String messageId, String newContent)? onEditMessage;

  /// 送信済みメッセージの送信取り消し（相手側にも痕跡を残さず完全に削除）。
  /// nullなら送信取り消し機能自体を提供しない。
  final Future<void> Function(String messageId)? onUnsendMessage;

  /// メッセージへのリアクションを設定・解除する（emojiがnullなら解除）。
  /// nullならリアクション機能自体を提供しない。
  final Future<void> Function(String messageId, String? emoji)? onSetReaction;

  /// この会話で既読機能を使うかどうか（ハンバーガーメニューの設定を反映）。
  /// falseの場合、自分の既読は記録されず、チェックマークも表示しない。
  final bool readReceiptsEnabled;

  /// 表示中の未読メッセージ（自分が送信者ではないもの）を既読にする処理。
  /// [readReceiptsEnabled]がtrueのときのみ呼ばれる。
  final Future<void> Function(List<String> messageIds)? onMarkRead;

  /// 音声通話の発信ボタン。一対（1対1）のみで渡す（グループ通話は未対応）。
  final VoidCallback? onCallPressed;

  /// ビデオ通話の発信ボタン。一対（1対1）のみで渡す（グループ通話は未対応）。
  final VoidCallback? onVideoCallPressed;

  /// 呼び出し側固有のAppBarアクション（例: 広場の詳細を開くボタン）。
  final List<Widget>? extraActions;

  /// メッセージ一覧の上に常時表示するバナー（例: 絶縁の提案・同意待ち通知）。
  final Widget? banner;

  /// 相手（自分以外）のアイコン・呼び名をタップした時の処理。広場のみ渡す
  /// （一対の相手は仕組み上必ず既に友達のため不要、DmChatPaneはnullのまま）。
  final void Function(String userId)? onSenderTap;

  /// 送信者の呼び名のフォントカラーを決める（広場のカスタムロール機能、
  /// 2026-07-28追加）。nullを返す・このフィールド自体がnullの場合は既定色
  /// （[ColorScheme.onSurfaceVariant]）のまま。一対では常にnull（ロールが
  /// 存在しないため）。
  final Color? Function(String userId)? senderNameColorResolver;

  /// 選択したメッセージを自分のアカウントから見えなくする（範囲選択削除）。
  /// nullなら選択モード自体を提供しない。
  final Future<void> Function(List<String> messageIds)? onHideMessages;

  /// アカウント削除通知メッセージの「いいえ」。DM（[isDm]）のみ渡す
  /// （広場は常にボタンなし表示のみのため不要）。
  final Future<void> Function(String messageId)? onDeclineAccountDeletionNotice;

  /// アカウント削除通知メッセージの「はい」（確認ダイアログの上で呼ばれる）。
  /// この語らい自体を物理削除する。DM（[isDm]）のみ渡す。
  final Future<void> Function()? onDeleteAfterAccountDeletion;

  /// 返信を含んだメッセージをタップした時、返信先が現在ロード済み（直近50件）
  /// の範囲に無かった場合に、その周辺のメッセージをまとめて取得する
  /// （`DirectMessageRepository.getMessagesAround`/
  /// `GroupRepository.getRoomMessagesAround`参照）。nullなら未対応として
  /// 何もしない（ジャンプできない）。
  final Future<List<Message>> Function(String messageId)? onFetchMessagesAround;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  late bool _hasHardwareKeyboard;

  /// メッセージ一覧のスクロール位置を、自動スクロール機能から直接操作する
  /// ために持つ（返信先ジャンプ機能は従来通りcontextベースの
  /// `Scrollable.ensureVisible`を使うため、この`controller`を必要としない）。
  final _scrollController = ScrollController();

  /// 自動スクロール開始位置（画面座標）を表示するアイコンの位置計算に使う。
  final _autoScrollAreaKey = GlobalKey();

  /// ミドルクリック/長押しによる自動スクロールの基準位置（画面座標）。
  /// nullなら非アクティブ（2026-07-29追加、ブラウザのミドルクリック
  /// オートスクロールと同じ挙動を、メッセージ行の吹き出し横の余白の長押しにも
  /// 割り当てている）。
  Offset? _autoScrollOrigin;

  /// 現在のポインタ位置と[_autoScrollOrigin]との縦距離。プラスなら下、
  /// マイナスなら上に離れている。
  double _autoScrollDy = 0;

  Ticker? _autoScrollTicker;
  Duration _autoScrollLastTick = Duration.zero;

  static const _autoScrollDeadZone = 12.0;
  static const _autoScrollMaxSpeed = 1350.0;

  void _startAutoScroll(Offset origin) {
    _autoScrollTicker?.dispose();
    _autoScrollLastTick = Duration.zero;
    setState(() {
      _autoScrollOrigin = origin;
      _autoScrollDy = 0;
    });
    _autoScrollTicker = createTicker(_tickAutoScroll)..start();
  }

  void _updateAutoScrollPosition(Offset position) {
    if (_autoScrollOrigin == null) return;
    setState(() => _autoScrollDy = position.dy - _autoScrollOrigin!.dy);
  }

  void _stopAutoScroll() {
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    if (_autoScrollOrigin == null) return;
    setState(() => _autoScrollOrigin = null);
  }

  /// ミドルクリックは「押して離す」でオン/オフを切り替える（一般的な
  /// ブラウザの挙動に合わせる）。既にアクティブな間はどのボタンのクリックでも
  /// 終了させる。
  void _handleMiddlePointerDown(PointerDownEvent event) {
    if (_autoScrollOrigin != null) {
      _stopAutoScroll();
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kMiddleMouseButton) != 0) {
      _startAutoScroll(event.position);
    }
  }

  /// 自動スクロール中、基準位置に表示する小さいアイコン
  /// （ブラウザのミドルクリックオートスクロールと同じ見た目）。
  Widget _buildAutoScrollIndicator() {
    final box =
        _autoScrollAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = _autoScrollOrigin;
    if (box == null || origin == null) return const SizedBox.shrink();
    final local = box.globalToLocal(origin);
    return Positioned(
      left: local.dx - 20,
      top: local.dy - 20,
      child: IgnorePointer(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.unfold_more, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  void _tickAutoScroll(Duration elapsed) {
    final dtSeconds =
        (elapsed - _autoScrollLastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _autoScrollLastTick = elapsed;
    if (dtSeconds <= 0 || !_scrollController.hasClients) return;
    final dy = _autoScrollDy;
    if (dy.abs() <= _autoScrollDeadZone) return;
    final overshoot = dy.abs() - _autoScrollDeadZone;
    // 基準位置から離れるほど速くスクロールする（ブラウザのオートスクロールと
    // 同じ挙動）。
    final speed = (overshoot * 6).clamp(0.0, _autoScrollMaxSpeed);
    // reverse:trueのListViewでは、pixelsが大きいほど古いメッセージ側
    // （画面上では上方向）へスクロールする。ポインタを下（dy>0）へ動かした
    // 時は新しいメッセージ側（画面上では下方向）へスクロールしたいので、
    // pixelsを減らす向きになる。
    final delta = dtSeconds * speed * (dy > 0 ? -1 : 1);
    final position = _scrollController.position;
    final next = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.jumpTo(next);
  }

  /// 既に既読リクエストを送った（または送信中の）メッセージIDの集合。
  /// Firestoreからの再送信のたびに同じメッセージへ既読を送り直さないための重複防止。
  final _markedReadIds = <String>{};

  /// メッセージの範囲選択削除モード。1件を長押しすると入り、以降はタップで
  /// 選択のオン/オフを切り替える（連続していない複数選択も可能）。
  bool _selecting = false;
  final _selectedMessageIds = <String>{};

  /// 返信中・編集中のメッセージ（同時にはどちらか一方のみ）。入力欄上部に
  /// プレビューバーとして表示し、キャンセルボタンでnullに戻す。
  Message? _replyingTo;
  Message? _editingMessage;

  /// 返信先ジャンプ機能用に、現在ロード済みの各メッセージ行へのGlobalKey。
  /// ListView.builderの遅延ビルドだと画面外（未ビルド）の返信先メッセージへは
  /// Scrollable.ensureVisibleが効かないため、下のbuild()でListView（非lazy）に
  /// 切り替えている（現在ロード済みメッセージは最新50件程度に収まる想定）。
  final _messageKeys = <String, GlobalKey>{};

  /// [widget.messagesStream]の直近50件に含まれない返信先へジャンプする際、
  /// [widget.onFetchMessagesAround]で1回だけ取得したメッセージを一時的に
  /// 保持しておく置き場（購読はしないので、ここに置かないと再ビルドのたびに
  /// 消えてしまう）。build()で[widget.messagesStream]の内容とマージして表示する。
  final _extraMessages = <String, Message>{};

  /// ジャンプ直後に対象メッセージを一瞬ハイライトするための状態。
  String? _highlightedMessageId;

  Future<void> _jumpToMessage(String messageId) async {
    if (!_messageKeys.containsKey(messageId)) {
      final fetched = await widget.onFetchMessagesAround?.call(messageId);
      if (fetched == null || fetched.isEmpty || !mounted) return;
      setState(() {
        for (final message in fetched) {
          _extraMessages[message.messageId] = message;
        }
      });
      // 取得したメッセージの行が実際にビルドされ、GlobalKeyにcurrentContextが
      // 付くまで1フレーム待つ（setState直後はまだ間に合わない）。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final key = _messageKeys[messageId];
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  void _startReply(Message message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
  }

  void _startEdit(Message message) {
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _textController.text = message.content;
    });
  }

  void _cancelComposerContext() {
    final wasEditing = _editingMessage != null;
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
      if (wasEditing) _textController.clear();
    });
  }

  void _enterSelectionMode(String messageId) {
    setState(() {
      _selecting = true;
      _selectedMessageIds
        ..clear()
        ..add(messageId);
    });
  }

  void _toggleSelected(String messageId) {
    setState(() {
      if (!_selectedMessageIds.remove(messageId)) {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selecting = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.chatDeleteConfirmTitle),
        content: Text(strings.chatDeleteConfirmMessage),
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
            child: Text(strings.chatDeleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = _selectedMessageIds.toList();
    _exitSelectionMode();
    await widget.onHideMessages?.call(ids);
  }

  /// 新しく届いたメッセージのうち、まだ自分が読んでいないものを既読にする。
  /// 書き込みが失敗した場合（通信不安定・画面を閉じるタイミング等）は
  /// [_markedReadIds]から外し、次回のスナップショット受信時に再試行できる
  /// ようにする（投げっぱなしで失敗を握りつぶすと、二度と既読が付かなくなる）。
  Future<void> _markUnreadMessages(List<Message> messages) async {
    if (!widget.readReceiptsEnabled || widget.onMarkRead == null) return;
    final toMark = messages
        .where((m) => m.senderId != widget.currentUserId)
        .where((m) => !m.readBy.any((r) => r.userId == widget.currentUserId))
        .where((m) => _markedReadIds.add(m.messageId))
        .map((m) => m.messageId)
        .toList();
    if (toMark.isEmpty) return;
    try {
      await widget.onMarkRead!(toMark);
    } catch (_) {
      _markedReadIds.removeAll(toMark);
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ChatScreenは会話単位のKey（dm-$dmId/group-$groupId）でのみ区別されて
    // おり、currentUserId自体はKeyに含まれない。万一同一Widgetインスタンスが
    // 別ユーザーに使い回された場合に既読の取りこぼしが起きないよう、
    // ユーザーが変わったら重複防止セットをリセットする。
    if (oldWidget.currentUserId != widget.currentUserId) {
      _markedReadIds.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    // Windows/Linux/macOSは常に物理キーボード前提のデスクトップOSなので
    // 最初から接続済み扱いにする。Android/iOS/Webはソフトウェアキーボードのみの
    // 場合もあるため、実際に物理キーのキー押下イベントを一度でも受け取った
    // 時点で初めて「接続されている」とみなす（OSからキーボード接続有無を
    // 直接問い合わせるAPIがFlutterに無いための代替判定）。
    _hasHardwareKeyboard = switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
      _ => false,
    };
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
  }

  bool _onHardwareKeyEvent(KeyEvent event) {
    // Enter/NumpadEnterは判定材料にしない。AndroidではtextInputAction.newline
    // を指定した多重行入力欄で、ソフトウェアキーボードの改行キーを押しただけでも
    // （物理キーボードが無くても）ハードウェアキーイベントとして届いてしまうため
    // （AndroidのIMEが改行用の専用エディタアクションを持たず、代わりに生の
    // Enterキーイベントを送出する仕様）、これを物理キーボード接続の根拠にすると
    // ソフトウェアキーボードしか無い端末で誤検知してしまう。文字キーなど
    // Enter以外のキーイベントは、通常IME経由のテキスト入力ではなく実機の
    // キー入力でしか発生しないため、そのまま判定材料として使える。
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!_hasHardwareKeyboard && event is KeyDownEvent) {
      setState(() => _hasHardwareKeyboard = true);
    }
    return false;
  }

  Future<void> _send({bool silent = false}) async {
    final content = _textController.text.trim();
    if (content.isEmpty) return;

    if (_editingMessage != null) {
      final messageId = _editingMessage!.messageId;
      _textController.clear();
      setState(() => _editingMessage = null);
      await widget.onEditMessage?.call(messageId, content);
      return;
    }

    final replyTo = _replyingTo;
    _textController.clear();
    setState(() => _replyingTo = null);
    await widget.onSend(content, silent: silent, replyTo: replyTo);
  }

  /// メッセージ入力欄でのEnterキー処理。設定（[SendKeyMode]）に応じて、
  /// 送信・相手に通知しない送信・改行のどれを行うかを自前で判定する。
  /// TextFieldの既定のEnter処理（ハードウェアキーボードからの生キーイベントに
  /// 対しては、プラットフォームのIME経由の改行挿入が常に走るとは限らない）に
  /// 依存すると環境によって改行が入らないことがあったため、改行も自前で挿入する。
  ///
  /// [_hasHardwareKeyboard]がfalseの間は何もしない（ignoredを返す）。
  /// ソフトウェアキーボードしか無い端末でも、textInputAction.newlineの
  /// 仕様上Enterキーが生イベントとして届くため、ここで自前の送信判定を
  /// 適用してしまうとTextField既定の改行挿入より先に横取りしてしまい、
  /// 改行が一切できなくなる（Enterを押すたびに送信されてしまう）。
  ///
  /// キー割り当て（物理キーボード接続時のみ）:
  /// - Enterで送信モード: Enter=送信 / Shift+Enter=改行 / Ctrl+Enter=通知せず送信
  /// - Ctrl+Enterで送信モード: Enter=改行 / Ctrl+Enter=送信 / Ctrl+Shift+Enter=通知せず送信
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_hasHardwareKeyboard) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final mode = ref.read(sendKeyModeProvider);
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (mode == SendKeyMode.enterToSend) {
      if (ctrlPressed) {
        _send(silent: true);
      } else if (shiftPressed) {
        _insertNewline();
      } else {
        _send();
      }
    } else {
      if (ctrlPressed && shiftPressed) {
        _send(silent: true);
      } else if (ctrlPressed) {
        _send();
      } else {
        _insertNewline();
      }
    }
    return KeyEventResult.handled;
  }

  void _insertNewline() {
    final selection = _textController.selection;
    final text = _textController.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, '\n');
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    _textController.dispose();
    _scrollController.dispose();
    _autoScrollTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final locale = ref.watch(appLocaleProvider);
    final layoutStyle = ref.watch(chatLayoutStyleProvider);
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final floatingShadow =
        Theme.of(context).extension<AppThemeExtras>()?.floatingShadow ??
            AppThemeExtras.none;

    return Scaffold(
      backgroundColor: isGekiga ? _kGekigaBackground : null,
      appBar: AppBar(
        backgroundColor: isGekiga ? _kGekigaBackground : null,
        foregroundColor: isGekiga ? Colors.white : null,
        automaticallyImplyLeading: false,
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: Text(
          _selecting
              ? strings.chatSelectionModeTitle(_selectedMessageIds.length)
              : widget.title,
        ),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: strings.chatDeleteSelectedTooltip,
                  onPressed:
                      _selectedMessageIds.isEmpty ? null : _confirmDeleteSelected,
                ),
              ]
            : [
                if (widget.onCallPressed != null)
                  IconButton(
                    icon: const Icon(Icons.call_outlined),
                    onPressed: widget.onCallPressed,
                  ),
                if (widget.onVideoCallPressed != null)
                  IconButton(
                    icon: const Icon(Icons.videocam_outlined),
                    onPressed: widget.onVideoCallPressed,
                  ),
                ...?widget.extraActions,
              ],
      ),
      body: Column(
        children: [
          if (widget.banner != null) widget.banner!,
          Expanded(
            child: Stack(
              key: _autoScrollAreaKey,
              children: [
                Listener(
                  // translucentにすることで、下のListView（左クリックでの
                  // ドラッグスクロール等）を邪魔せず、ミドルクリックの検出だけ
                  // 追加で行える（Listenerはジェスチャーアリーナに参加しない
                  // 生のポインタ通知のため、他のジェスチャー認識と競合しない）。
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleMiddlePointerDown,
                  onPointerHover: (event) =>
                      _updateAutoScrollPosition(event.position),
                  child: StreamBuilder<List<Message>>(
                    stream: widget.messagesStream,
                    builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('エラー: ${snapshot.error}'));
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(child: Text('まだメッセージはありません'));
                }
                _markUnreadMessages(messages);

                // 直近50件（messages、購読中）に、返信先ジャンプで一時的に
                // 取得したメッセージ（_extraMessages、購読していない）を
                // マージして表示する。同じidがあればmessages側を優先する
                // （購読中で最新のため）。既にmessagesに含まれるようになった
                // 分はもう保持しておく必要が無いので削除する。
                _extraMessages.removeWhere(
                  (id, _) => messages.any((m) => m.messageId == id),
                );
                final combined = [
                  ...messages,
                  ..._extraMessages.values,
                ]..sort((a, b) {
                    final aTime = a.sentAt?.toDate() ?? DateTime.now();
                    final bTime = b.sentAt?.toDate() ?? DateTime.now();
                    return bTime.compareTo(aTime);
                  });

                // 返信元メッセージの引用プレビュー・返信先ジャンプに使う。
                // 現在ロード済み（直近50件＋ジャンプで追加取得した分）の
                // 範囲に返信元があれば、こちらを優先して表示する（編集済み
                // なら最新の内容を反映できる）。範囲外ならMessage側の
                // 非正規化フィールド（replyToSnippet等）にフォールバックする
                // （_MessageRow参照）。
                final messagesById = {
                  for (final m in combined) m.messageId: m,
                };

                // 画面外に流れたメッセージのGlobalKeyは溜め続けない。
                final currentIds = messagesById.keys.toSet();
                _messageKeys.removeWhere((id, _) => !currentIds.contains(id));

                // combinedは新しい順（index 0が最新）。日付区切りを「その日の
                // 最初のメッセージの直上」に挿入したいので、一旦古い順に走査して
                // 区切り込みのリストを組み立ててから反転する。reverse:trueの
                // ListViewにそのまま渡すと、index 0（リストの末尾＝一番新しい
                // 要素）が画面下端に来て、見た目は上から古い順（区切り→その日の
                // メッセージ…）に正しく並ぶ。
                final entries = <Widget>[];
                DateTime? currentDay;
                for (var i = combined.length - 1; i >= 0; i--) {
                  final message = combined[i];
                  final sentAt = message.sentAt?.toDate();
                  if (sentAt != null &&
                      (currentDay == null || !isSameDay(sentAt, currentDay))) {
                    currentDay = sentAt;
                    entries.add(_DateSeparator(date: sentAt, locale: locale));
                  }
                  entries.add(
                    _MessageRow(
                      key: _messageKeys.putIfAbsent(
                        message.messageId,
                        GlobalKey.new,
                      ),
                      message: message,
                      isMe: message.senderId == widget.currentUserId,
                      currentUserId: widget.currentUserId,
                      timeLabel: sentAt != null
                          ? formatMessageTime(sentAt, timeFormat)
                          : null,
                      colorScheme: colorScheme,
                      floatingShadow: floatingShadow,
                      uiStyle: uiStyle,
                      readReceiptsEnabled: widget.readReceiptsEnabled,
                      layoutStyle: layoutStyle,
                      isDm: widget.isDm,
                      conversationId: widget.conversationId,
                      onSenderTap: _selecting ? null : widget.onSenderTap,
                      senderNameColorResolver: widget.senderNameColorResolver,
                      selecting: _selecting,
                      selected: _selectedMessageIds.contains(message.messageId),
                      canSelect: widget.onHideMessages != null,
                      onEnterSelection: _enterSelectionMode,
                      onToggleSelected: _toggleSelected,
                      messagesById: messagesById,
                      onReply: _startReply,
                      onEdit: widget.onEditMessage != null ? _startEdit : null,
                      onUnsend: widget.onUnsendMessage,
                      onSetReaction: widget.onSetReaction,
                      onJumpToReply: _jumpToMessage,
                      highlighted: _highlightedMessageId == message.messageId,
                      timeFormat: timeFormat,
                      onDeclineAccountDeletionNotice:
                          widget.onDeclineAccountDeletionNotice,
                      onDeleteAfterAccountDeletion:
                          widget.onDeleteAfterAccountDeletion,
                      onAutoScrollStart: _selecting ? null : _startAutoScroll,
                      onAutoScrollUpdate:
                          _selecting ? null : _updateAutoScrollPosition,
                      onAutoScrollEnd: _selecting ? null : _stopAutoScroll,
                    ),
                  );
                }
                final reversedEntries = entries.reversed.toList();

                // 返信先ジャンプ機能（Scrollable.ensureVisible）は対象行が
                // 既にツリー上にビルドされている必要があるため、遅延ビルドの
                // ListView.builderではなく全件ビルド済みのListViewを使う
                // （現在ロード済みメッセージは最新50件程度に収まる想定）。
                return ListView(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  children: reversedEntries,
                );
                    },
                  ),
                ),
                if (_autoScrollOrigin != null) _buildAutoScrollIndicator(),
              ],
            ),
          ),
          if (!_selecting && (_replyingTo != null || _editingMessage != null))
            _ComposerContextBar(
              replyingTo: _replyingTo,
              editing: _editingMessage != null,
              strings: strings,
              onCancel: _cancelComposerContext,
            ),
          if (!_selecting)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleKeyEvent,
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: 'メッセージを入力',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 物理キーボード接続の判定に関わらず、何か入力されている間は
                  // 常に送信ボタンを表示する（判定を誤っても送信手段が
                  // 無くならないようにするため）。
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _send,
                          onLongPress: () => _send(silent: true),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(Icons.send, color: colorScheme.primary),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 入力欄の上に表示する「返信先」「編集中」プレビューバー。閉じるボタンで
/// [onCancel]（返信・編集どちらもキャンセルして通常入力に戻す）を呼ぶ。
class _ComposerContextBar extends StatelessWidget {
  const _ComposerContextBar({
    required this.replyingTo,
    required this.editing,
    required this.strings,
    required this.onCancel,
  });

  final Message? replyingTo;
  final bool editing;
  final Strings strings;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            editing ? Icons.edit : Icons.reply,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: editing
                ? Text(
                    strings.chatEditingLabel,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.chatReplyingToLabel(
                          replyingTo?.senderRhingId != null
                              ? '@${replyingTo!.senderRhingId}'
                              : '?',
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        messageSnippetOf(replyingTo?.content ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
            tooltip: strings.cancel,
          ),
        ],
      ),
    );
  }
}

/// メッセージ一覧の日付区切り。その日最初のメッセージの直上に、画面中央の
/// 丸みを帯びたラベルとして表示する。LINE等の「今日」「昨日」のような相対
/// 表記ではなく、常に絶対日付（yyyy/mm/dd）で表す。
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.locale});

  final DateTime date;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            formatMessageDate(date, locale),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// メッセージ1件分の表示。設定（[ChatLayoutStyle]、設定＞アプリケーションから
/// 変更可能）に応じて2つの見た目を切り替える。この設定は自分の端末での表示
/// にのみ影響し、相手の語らいの見え方には影響しない。
///
/// - [ChatLayoutStyle.sideBySide]（既定）: 自分は右寄せ・相手は左寄せ。
///   自分のアイコンは表示しない。一対（1対1）では相手のアイコン・呼び名も
///   表示しない（広場では引き続き表示する）。
/// - [ChatLayoutStyle.allLeft]: 自分・相手ともに左寄せで、常にアイコン・
///   呼び名を表示する。
///
/// どちらのスタイルでも、誰か（送信者以外）が既読にした場合は吹き出しの角に
/// チェックマークを表示する（自分のメッセージは左下、相手のメッセージは
/// 右下）。タップすると既読者一覧がポップアップで出る。
class _MessageRow extends ConsumerWidget {
  const _MessageRow({
    required this.message,
    required this.isMe,
    required this.currentUserId,
    required this.timeLabel,
    required this.colorScheme,
    required this.floatingShadow,
    this.uiStyle = AppUiStyle.simple,
    required this.readReceiptsEnabled,
    required this.layoutStyle,
    required this.isDm,
    this.conversationId,
    this.onSenderTap,
    this.senderNameColorResolver,
    this.selecting = false,
    this.selected = false,
    this.canSelect = false,
    this.onEnterSelection,
    this.onToggleSelected,
    this.messagesById = const {},
    this.onReply,
    this.onEdit,
    this.onUnsend,
    this.onSetReaction,
    this.onJumpToReply,
    this.highlighted = false,
    this.timeFormat = MessageTimeFormat.h24,
    this.onDeclineAccountDeletionNotice,
    this.onDeleteAfterAccountDeletion,
    this.onAutoScrollStart,
    this.onAutoScrollUpdate,
    this.onAutoScrollEnd,
    super.key,
  });

  final Message message;
  final bool isMe;
  final String currentUserId;
  final String? timeLabel;
  final ColorScheme colorScheme;
  final List<BoxShadow> floatingShadow;

  /// メッセージ画面の見た目スタイル（2026-07-29追加）。[AppUiStyle.gekiga]の
  /// 間、吹き出し・アイコンを手描き風のギザギザ表示に切り替える。
  final AppUiStyle uiStyle;
  final bool readReceiptsEnabled;
  final ChatLayoutStyle layoutStyle;
  final bool isDm;

  /// このメッセージが属する会話（一対のdmId・広場のgroupId）。会話ごとに
  /// 使うプロフィールカード（2026-07-29追加）を反映して送信者名・アイコンを
  /// 表示するために[_SenderName]/[_SenderAvatar]へ伝播する。
  final String? conversationId;

  final void Function(String userId)? onSenderTap;
  final Color? Function(String userId)? senderNameColorResolver;

  /// 範囲選択削除モード中かどうか（[ChatScreen.onHideMessages]が渡されて
  /// いる場合のみ長押しで入れる）。
  final bool selecting;
  final bool selected;
  final bool canSelect;
  final void Function(String messageId)? onEnterSelection;
  final void Function(String messageId)? onToggleSelected;

  /// 現在ロード済みの（最新50件の）メッセージ一覧。返信先の引用プレビューを
  /// 最新の内容で表示するためのルックアップに使う（見つからない場合は
  /// [Message.replyToSnippet]等の非正規化フィールドにフォールバックする）。
  final Map<String, Message> messagesById;

  final void Function(Message message)? onReply;

  /// nullなら編集メニュー自体を出さない（自分の投稿でも[ChatScreen.onEditMessage]
  /// が渡されていない、または対象がテキストメッセージでない場合）。
  final void Function(Message message)? onEdit;

  /// nullなら送信取り消しメニュー自体を出さない。
  final void Function(String messageId)? onUnsend;

  /// nullならリアクション機能自体を出さない。
  final void Function(String messageId, String? emoji)? onSetReaction;

  /// 返信を含んだメッセージをタップした時に、返信先メッセージへジャンプする。
  /// [messagesById]に返信先が無い（直近50件のロード範囲外）場合は、
  /// 呼び出し先（`_ChatScreenState._jumpToMessage`）が
  /// [ChatScreen.onFetchMessagesAround]で取得してからジャンプする。
  final void Function(String messageId)? onJumpToReply;

  /// 返信先ジャンプ直後、対象メッセージだと分かるよう一瞬背景を強調する。
  final bool highlighted;

  /// contentType='call'（通話サマリー）の開始時刻表示に使う時刻表示形式。
  final MessageTimeFormat timeFormat;

  /// contentType='accountDeleted'通知への「いいえ」。DMのみ渡される。
  final Future<void> Function(String messageId)? onDeclineAccountDeletionNotice;

  /// contentType='accountDeleted'通知への「はい」（確認ダイアログの上で
  /// 呼ばれる）。DMのみ渡される。
  final Future<void> Function()? onDeleteAfterAccountDeletion;

  /// 吹き出し横の余白（[_MessageInteractions]参照）を長押しすると、
  /// ミドルクリックと同じ自動スクロールを開始する（2026-07-29追加）。
  final ValueChanged<Offset>? onAutoScrollStart;
  final ValueChanged<Offset>? onAutoScrollUpdate;
  final VoidCallback? onAutoScrollEnd;

  /// チェックマークバッジ（[badgeContext]）の真下から伸びる形でポップアップを
  /// 表示する。画面全体をグレーアウトしないよう、barrierColorは透明にする
  /// （ダイアログのような背景の暗転はしない、メニューに近い見た目）。
  /// バッジより下の余白が足りない場合（画面下の方のメッセージ）は、途中で
  /// 途切れないようバッジの上に伸びる形に切り替える。
  void _showReadReceiptPopup(
    BuildContext context,
    BuildContext badgeContext,
    List<MessageReadReceipt> readers,
    Strings strings,
  ) {
    final badgeBox = badgeContext.findRenderObject()! as RenderBox;
    final badgeRect = badgeBox.localToGlobal(Offset.zero) & badgeBox.size;
    const width = 240.0;
    const minPopupSpace = 160.0;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenSize = MediaQuery.sizeOf(context);
        final left =
            badgeRect.left.clamp(8.0, screenSize.width - width - 8.0);
        final spaceBelow = screenSize.height - badgeRect.bottom;
        final showAbove = spaceBelow < minPopupSpace && badgeRect.top > spaceBelow;
        final top = showAbove ? null : badgeRect.bottom + 4;
        final bottom =
            showAbove ? screenSize.height - badgeRect.top + 4 : null;
        final maxHeight = showAbove
            ? badgeRect.top - 24
            : screenSize.height - badgeRect.bottom - 24;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              bottom: bottom,
              child: Material(
                color: colorScheme.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: width,
                    maxHeight: maxHeight,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          strings.readReceiptPopupTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: readers.length,
                          itemBuilder: (context, index) {
                            final reader = readers[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  _SenderAvatar(
                                    userId: reader.userId,
                                    rhingId: null,
                                    conversationId: conversationId,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SenderName(
                                      userId: reader.userId,
                                      rhingId: null,
                                      conversationId: conversationId,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final readers =
        message.readBy.where((r) => r.userId != message.senderId).toList();
    // 一対（1対1）では、相手のメッセージに付く既読マークは「自分が相手の
    // メッセージを読んだか」を示すだけで意味が無いため非表示にする
    // （読み取り・記録自体はやめない。既読の記録をやめると、自分の
    // メッセージを相手が読んだかの追跡もできなくなってしまうため）。
    // 自分のメッセージには引き続き既読マークを表示し、相手が読んだかを
    // 追跡できるようにする。広場（グループ）はこれまで通り両方に表示する。
    final showReadMark =
        readReceiptsEnabled && readers.isNotEmpty && !(isDm && !isMe);
    // 一対の自分のメッセージは、相手（1人しかいない）が読んだかどうかの
    // 有無だけ分かれば十分で、人数や「誰が読んだか」の一覧は意味を持たない
    // ため、✓のみを表示しタップしても何も起きないようにする。
    final isSimpleDmReadMark = isDm && isMe;
    // sideBySideで自分のメッセージの時だけ右寄せ。それ以外
    // （sideBySideで相手、またはallLeftで自分・相手いずれも）は左寄せ。
    final alignRight = layoutStyle == ChatLayoutStyle.sideBySide && isMe;

    final isGekiga = uiStyle == AppUiStyle.gekiga;
    // 劇画スタイルはモノクロで白黒反転して自分/相手を描き分ける
    // （自分は白地に黒文字、相手は黒地に白文字、2026-07-29修正）。
    final onBubbleColor = isGekiga
        ? (isMe ? Colors.black : Colors.white)
        : (isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant);

    // 返信元の引用プレビュー。ロード済み（最新50件）の範囲に返信元の実物が
    // あればそちらを優先して表示し（編集済みなら最新内容を反映できる）、
    // 無ければ送信時点の非正規化フィールドにフォールバックする
    // （送信取り消しされた場合はunsendMessage/unsendRoomMessageがこれらの
    // フィールドをまとめてクリアするため、その場合は引用プレビュー自体が
    // 表示されなくなる）。
    Widget? replyPreview;
    if (message.replyToMessageId != null) {
      final target = messagesById[message.replyToMessageId];
      final replySenderId = target?.senderId ?? message.replyToSenderId;
      final replySenderRhingId = target?.senderRhingId ?? message.replyToSenderRhingId;
      final snippet = target != null
          ? messageSnippetOf(target.content)
          : (message.replyToSnippet ?? '');
      if (replySenderId != null) {
        replyPreview = Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: onBubbleColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SenderName(
                userId: replySenderId,
                rhingId: replySenderRhingId,
                conversationId: conversationId,
              ),
              Text(
                snippet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: onBubbleColor),
              ),
            ],
          ),
        );
      }
    }

    final isCallSummary = message.contentType == 'call';
    final isAccountDeletedNotice = message.contentType == 'accountDeleted';

    final bubbleContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?replyPreview,
        if (isCallSummary)
          _callSummaryContent(onBubbleColor)
        else if (isAccountDeletedNotice)
          _accountDeletedContent(context, ref, strings, onBubbleColor)
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: LinkifiedText(
                  message.content,
                  style: TextStyle(
                    color: onBubbleColor,
                    fontWeight: isGekiga ? FontWeight.w600 : null,
                  ),
                  linkColor: isGekiga
                      ? (isMe ? Colors.black : Colors.white)
                      : (isMe ? colorScheme.onPrimary : colorScheme.primary),
                ),
              ),
              if (message.silent) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.notifications_off,
                  size: 14,
                  color: onBubbleColor.withValues(alpha: 0.7),
                ),
              ],
              if (message.editedAt != null) ...[
                const SizedBox(width: 4),
                Text(
                  strings.chatEditedLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: onBubbleColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
      ],
    );

    final bubble = isGekiga
        ? _GekigaBubble(
            seed: message.messageId.hashCode,
            isMe: isMe,
            child: bubbleContent,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: floatingShadow,
            ),
            child: bubbleContent,
          );

    // 吹き出しの角に既読チェックマークを重ねる。バブルが右寄せの時は左下、
    // 左寄せの時は右下（吹き出しの中心寄り＝アイコンと反対側）に表示する
    // （isMeではなくalignRightで決める。allLeftスタイルでは自分のメッセージも
    // 左寄せになるため、isMeだけで判定すると常にアイコン側に重なってしまう）。
    // 吹き出しの内容（特に画像だけの小さい吹き出し）に重ならないよう、
    // 角からしっかり離す。
    // テキストメッセージの自分の投稿のみ編集可能（画像等contentType='text'
    // 以外は将来実装時もまず本文編集の対象外という方針、Planでの検討通り）。
    final canEdit = isMe && message.contentType == 'text' && onEdit != null;

    final badgeContent = isSimpleDmReadMark
        ? Icon(Icons.done, size: 12, color: colorScheme.primary)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done, size: 12, color: colorScheme.primary),
              const SizedBox(width: 2),
              Text(
                '${readers.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: floatingShadow,
      ),
      child: badgeContent,
    );

    final replyTargetId = message.replyToMessageId;
    final onBubbleTap = (replyTargetId != null && onJumpToReply != null)
        ? () => onJumpToReply!(replyTargetId)
        : null;

    // 長押し/右クリックでリアクション・返信・編集等のメニューを開く判定は
    // 吹き出し本体だけに絞る（2026-07-29変更）。以前は行全体（余白込み）が
    // 対象だったが、余白部分の長押しは自動スクロール（[_MessageInteractions]
    // 参照）に割り当てたため、両者が同じ操作を奪い合わないよう分離した。
    final bubbleWithReadMark = _MessageBubbleTapArea(
      canSelect: canSelect,
      strings: strings,
      onTap: onBubbleTap,
      onReply: () => onReply?.call(message),
      onEdit: canEdit ? () => onEdit?.call(message) : null,
      onUnsend: (isMe && onUnsend != null)
          ? () => _confirmUnsend(context, strings)
          : null,
      onReact: onSetReaction == null
          ? null
          : (emoji) {
              final mine = message.reactions[currentUserId];
              onSetReaction?.call(
                message.messageId,
                mine == emoji ? null : emoji,
              );
            },
      onSelect: canSelect
          ? () => onEnterSelection?.call(message.messageId)
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          if (showReadMark)
            Positioned(
              bottom: -14,
              left: alignRight ? -10 : null,
              right: alignRight ? null : -10,
              child: isSimpleDmReadMark
                  ? badge
                  : Builder(
                      builder: (badgeContext) => GestureDetector(
                        onTap: () => _showReadReceiptPopup(
                          context,
                          badgeContext,
                          readers,
                          strings,
                        ),
                        child: badge,
                      ),
                    ),
            ),
        ],
      ),
    );

    // allLeftでは自分・相手とも常にアイコン・呼び名を表示する。sideBySideでは
    // 自分のメッセージには表示せず、相手のメッセージも一対では表示しない
    // （広場では引き続き表示する）。
    final showAvatarAndName = layoutStyle == ChatLayoutStyle.allLeft
        ? true
        : (!isMe && !isDm);

    final timeText = timeLabel == null
        ? null
        : Text(
            timeLabel!,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          );

    final previewUrl = firstUrlIn(message.content);

    final Widget content;
    if (alignRight) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ?timeText,
              const SizedBox(height: 2),
              bubbleWithReadMark,
              if (previewUrl != null) LinkPreviewCard(url: previewUrl),
            ],
          ),
        ),
      );
    } else {
      final canTapSender = !isMe && onSenderTap != null;
      final senderAvatar = _SenderAvatar(
        userId: message.senderId,
        rhingId: message.senderRhingId,
        conversationId: conversationId,
        uiStyle: uiStyle,
      );
      final senderName = _SenderName(
        userId: message.senderId,
        rhingId: message.senderRhingId,
        conversationId: conversationId,
        color: senderNameColorResolver?.call(message.senderId),
      );

      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAvatarAndName) ...[
                canTapSender
                    ? GestureDetector(
                        onTap: () => onSenderTap!(message.senderId),
                        child: senderAvatar,
                      )
                    : senderAvatar,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showAvatarAndName)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: canTapSender
                                ? GestureDetector(
                                    onTap: () => onSenderTap!(message.senderId),
                                    child: senderName,
                                  )
                                : senderName,
                          ),
                          if (timeText != null) ...[
                            const SizedBox(width: 6),
                            timeText,
                          ],
                        ],
                      )
                    else
                      ?timeText,
                    const SizedBox(height: 2),
                    bubbleWithReadMark,
                    if (previewUrl != null) LinkPreviewCard(url: previewUrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget body;
    if (selecting) {
      // 範囲選択削除モード: タップで選択のオン/オフを切り替える。
      // 選択中はチェックボックスと薄い塗りで示す（開始自体は下記の
      // コンテキストメニューの「選択」項目から行う）。
      body = GestureDetector(
        onTap: () => onToggleSelected?.call(message.messageId),
        child: Container(
          color: selected ? colorScheme.primary.withValues(alpha: 0.12) : null,
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelected?.call(message.messageId),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    } else {
      body = _MessageInteractions(
        canEdit: canEdit,
        onReply: () => onReply?.call(message),
        onEdit: canEdit ? () => onEdit?.call(message) : null,
        onAutoScrollStart: onAutoScrollStart,
        onAutoScrollUpdate: onAutoScrollUpdate,
        onAutoScrollEnd: onAutoScrollEnd,
        child: content,
      );
    }

    final rowContent = message.reactions.isEmpty
        ? body
        : Column(
            crossAxisAlignment:
                alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [body, _reactionBar(alignRight)],
          );

    // 返信先ジャンプの着地先だと分かるよう、一瞬だけ背景を強調する。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlighted
          ? colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      child: rowContent,
    );
  }

  /// 通話履歴メッセージ（contentType='call'）の表示。「通話が終了しました」
  /// の下に、開始時刻と通話時間を添える（例: 「14:32から5分32秒」）。
  Widget _callSummaryContent(Color onBubbleColor) {
    final startedAt = message.callStartedAt?.toDate();
    final durationSeconds = message.callDurationSeconds;
    final isVideoCall = message.callIsVideo ?? false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isVideoCall ? Icons.videocam_outlined : Icons.call_outlined,
          size: 18,
          color: onBubbleColor,
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.content, style: TextStyle(color: onBubbleColor)),
            if (startedAt != null && durationSeconds != null)
              Text(
                '${formatMessageTime(startedAt, timeFormat)}から'
                '${_formatCallDuration(durationSeconds)}',
                style: TextStyle(
                  fontSize: 12,
                  color: onBubbleColor.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// contentType='accountDeleted'（アカウント削除通知）の表示。DMのみ、
  /// 未応答（[Message.accountDeletionResponse]がnull）の場合に「語らいを
  /// 削除しますか？」+ はい/いいえボタンを追加で出す。広場では常に通知文言
  /// のみ（[onDeclineAccountDeletionNotice]/[onDeleteAfterAccountDeletion]は
  /// 一対からしか渡されない）。
  Widget _accountDeletedContent(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Color onBubbleColor,
  ) {
    final label = message.senderRhingId != null
        ? '@${message.senderRhingId}'
        : message.senderId;
    final showPrompt = isDm &&
        message.accountDeletionResponse == null &&
        (onDeclineAccountDeletionNotice != null ||
            onDeleteAfterAccountDeletion != null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.chatAccountDeletedNotice(label),
          style: TextStyle(color: onBubbleColor),
        ),
        if (showPrompt) ...[
          const SizedBox(height: 4),
          Text(
            strings.chatAccountDeletedDeleteConversationPrompt,
            style: TextStyle(color: onBubbleColor),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => onDeclineAccountDeletionNotice
                    ?.call(message.messageId),
                child: Text(strings.chatAccountDeletedNoButton),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () =>
                    _confirmDeleteConversation(context, strings),
                child: Text(strings.chatAccountDeletedYesButton),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDeleteConversation(
    BuildContext context,
    Strings strings,
  ) async {
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
    if (confirmed == true) await onDeleteAfterAccountDeletion?.call();
  }

  static String _formatCallDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours時間$minutes分' : '$hours時間';
    }
    if (minutes > 0) {
      return seconds > 0 ? '$minutes分$seconds秒' : '$minutes分';
    }
    return '$seconds秒';
  }

  Widget _reactionBar(bool alignRight) {
    final counts = <String, int>{};
    for (final emoji in message.reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final myReaction = message.reactions[currentUserId];
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 4,
          children: [
            for (final entry in counts.entries)
              GestureDetector(
                onTap: onSetReaction == null
                    ? null
                    : () => onSetReaction!(
                          message.messageId,
                          myReaction == entry.key ? null : entry.key,
                        ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: myReaction == entry.key
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                    border: myReaction == entry.key
                        ? Border.all(color: colorScheme.primary)
                        : null,
                  ),
                  child: Text(
                    '${entry.key} ${entry.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnsend(BuildContext context, Strings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.chatUnsendConfirmTitle),
        content: Text(strings.chatUnsendConfirmMessage),
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
            child: Text(strings.chatUnsendConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) onUnsend?.call(message.messageId);
  }
}

enum _MessageMenuAction { reply, edit, unsend, react, select }

/// 吹き出し本体だけに絞った当たり判定。長押し/右クリックでリアクション・
/// 返信・編集等のコンテキストメニューを開く（2026-07-29変更: 以前は行全体
/// （余白込み）が対象だったが、余白部分の長押しを自動スクロール
/// （[_MessageInteractions]参照）に割り当てたため、両者が同じ操作を
/// 奪い合わないよう吹き出し本体だけに絞った）。
class _MessageBubbleTapArea extends StatelessWidget {
  const _MessageBubbleTapArea({
    required this.child,
    required this.canSelect,
    required this.strings,
    required this.onReply,
    this.onEdit,
    this.onUnsend,
    this.onReact,
    this.onSelect,
    this.onTap,
  });

  final Widget child;
  final bool canSelect;
  final Strings strings;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onUnsend;
  final void Function(String emoji)? onReact;
  final VoidCallback? onSelect;

  /// 返信先ジャンプ用のタップ。nullなら通常通りタップでは何も起きない。
  final VoidCallback? onTap;

  RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final action = await showMenu<_MessageMenuAction>(
      context: context,
      position: _menuPosition(context, globalPosition),
      items: [
        PopupMenuItem(
          value: _MessageMenuAction.reply,
          child: Text(strings.chatReplyAction),
        ),
        if (onReact != null)
          PopupMenuItem(
            value: _MessageMenuAction.react,
            child: Text(strings.chatReactAction),
          ),
        if (onEdit != null)
          PopupMenuItem(
            value: _MessageMenuAction.edit,
            child: Text(strings.chatEditAction),
          ),
        if (onUnsend != null)
          PopupMenuItem(
            value: _MessageMenuAction.unsend,
            child: Text(strings.chatUnsendAction),
          ),
        if (canSelect)
          PopupMenuItem(
            value: _MessageMenuAction.select,
            child: Text(strings.chatSelectAction),
          ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _MessageMenuAction.reply:
        onReply();
      case _MessageMenuAction.edit:
        onEdit?.call();
      case _MessageMenuAction.unsend:
        onUnsend?.call();
      case _MessageMenuAction.react:
        await _openReactionPicker(context, globalPosition);
      case _MessageMenuAction.select:
        onSelect?.call();
      case null:
        break;
    }
  }

  Future<void> _openReactionPicker(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final emoji = await showMenu<String>(
      context: context,
      position: _menuPosition(context, globalPosition),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in kReactionEmojis)
                InkWell(
                  onTap: () => Navigator.of(context).pop(emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (emoji != null) onReact?.call(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: (details) => _openMenu(context, details.globalPosition),
      onSecondaryTapDown: (details) => _openMenu(context, details.globalPosition),
      child: child,
    );
  }
}

/// 左スワイプ（軽く=返信、最後まで=編集。編集は[canEdit]がtrueの時のみ）と、
/// 吹き出し横の余白の長押し/ミドルクリックによる自動スクロール開始を扱う。
/// メニューを開く長押し/右クリックは吹き出し本体（[_MessageBubbleTapArea]）
/// 側に分離済みのため、ここでの長押しは自動スクロール専用になる
/// （2026-07-29変更）。選択モード中（[ChatScreen]の範囲選択削除）は使わない
/// （_MessageRow.build参照）。
class _MessageInteractions extends StatefulWidget {
  const _MessageInteractions({
    required this.child,
    required this.canEdit,
    required this.onReply,
    this.onEdit,
    this.onAutoScrollStart,
    this.onAutoScrollUpdate,
    this.onAutoScrollEnd,
  });

  final Widget child;
  final bool canEdit;
  final VoidCallback onReply;
  final VoidCallback? onEdit;

  final ValueChanged<Offset>? onAutoScrollStart;
  final ValueChanged<Offset>? onAutoScrollUpdate;
  final VoidCallback? onAutoScrollEnd;

  @override
  State<_MessageInteractions> createState() => _MessageInteractionsState();
}

class _MessageInteractionsState extends State<_MessageInteractions> {
  double _dragExtent = 0;

  static const _replyThreshold = -48.0;
  static const _editThreshold = -120.0;

  double get _minDrag => widget.canEdit ? _editThreshold : _replyThreshold;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent = (_dragExtent + details.delta.dx).clamp(_minDrag, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final reachedEdit = widget.canEdit && _dragExtent <= _editThreshold;
    final reachedReply = !reachedEdit && _dragExtent <= _replyThreshold;
    setState(() => _dragExtent = 0);
    if (reachedEdit) {
      widget.onEdit?.call();
    } else if (reachedReply) {
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 吹き出しの余白（アイコン側の空きスペース等）も同じ行なら反応するよう、
      // 実際に何か描画されている領域だけでなくAlign/Padding込みの行全体を
      // ヒットテスト対象にする（既定のdeferToChildだと、余白部分は下の
      // レンダーオブジェクトが自身を消費しないため反応しない）。
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onLongPressStart: (details) =>
          widget.onAutoScrollStart?.call(details.globalPosition),
      onLongPressMoveUpdate: (details) =>
          widget.onAutoScrollUpdate?.call(details.globalPosition),
      onLongPressEnd: (_) => widget.onAutoScrollEnd?.call(),
      onLongPressCancel: widget.onAutoScrollEnd,
      child: Stack(
        children: [
          if (_dragExtent < 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    widget.canEdit && _dragExtent <= _editThreshold
                        ? Icons.edit
                        : Icons.reply,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragExtent == 0
                ? const Duration(milliseconds: 150)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dragExtent, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// 送信者の呼び名。[AppUser.effectiveNickname]（適用中の工房カードがあれば
/// そちらを優先）があればそれを表示し、未設定ならRhing IDにフォールバックする。
class _SenderName extends ConsumerWidget {
  const _SenderName({
    required this.userId,
    required this.rhingId,
    this.conversationId,
    this.color,
  });

  final String userId;
  final String? rhingId;

  /// この送信者が使っている会話ごとのプロフィールカード（2026-07-29追加）を
  /// 反映するための会話id（一対のdmId・広場のgroupId）。nullなら標準の
  /// カードで表示する。
  final String? conversationId;

  /// 広場のカスタムロールで指定された色（`ChatScreen.senderNameColorResolver`
  /// 参照）。nullなら既定色のまま。
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref
        .watch(watchedUserProvider(userId))
        .value
        ?.effectiveNicknameFor(conversationId)
        ?.text;
    final label = (nickname != null && nickname.isNotEmpty)
        ? nickname
        : '@${rhingId ?? '?'}';
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 送信者のアイコン。蔵で設定した実際のアイコン（[AppUser.effectiveIcon]）が
/// あればそれを表示し、未設定ならRhing IDから生成する色分けイニシャルに
/// フォールバックする。
class _SenderAvatar extends ConsumerWidget {
  const _SenderAvatar({
    required this.userId,
    required this.rhingId,
    this.conversationId,
    this.uiStyle = AppUiStyle.simple,
  });

  final String userId;
  final String? rhingId;

  /// [_SenderName.conversationId]と同じ。
  final String? conversationId;

  /// [AppUiStyle.gekiga]の間、アイコンを手描き風の色ブロック＋白リングで
  /// 囲む（2026-07-29追加）。既読者一覧ポップアップ等、通常見た目のまま
  /// でよい呼び出し元は既定値[AppUiStyle.simple]のまま渡さなくてよい。
  final AppUiStyle uiStyle;

  static const _palette = [
    Color(0xFFEE7800),
    Color(0xFF6D4C41),
    Color(0xFF00897B),
    Color(0xFF5E35B1),
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(watchedUserProvider(userId)).value;
    final iconUrl = user?.effectiveIconFor(conversationId)?.url;
    final Widget avatar;
    if (iconUrl != null) {
      avatar = CircleAvatar(radius: 16, backgroundImage: NetworkImage(iconUrl));
    } else {
      final id = rhingId ?? '?';
      final color = _palette[id.hashCode.abs() % _palette.length];
      avatar = CircleAvatar(
        radius: 16,
        backgroundColor: color,
        child: Text(
          id[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      );
    }
    if (uiStyle != AppUiStyle.gekiga) return avatar;
    // 身だしなみ（蔵）の「イメージカラー」（AppUser.imageColor、0xRRGGBB）を
    // ユーザーごとの色として使う。未設定なら通常時のフォールバックと同じ
    // パレットから、rhingIdではなくuserIdのハッシュで選ぶ（rhingIdが
    // nullな呼び出し元でも安定した色になるようにするため）。
    final badgeColor = user?.imageColor != null
        ? Color(0xFF000000 | user!.imageColor!)
        : _palette[userId.hashCode.abs() % _palette.length];
    return _GekigaAvatarFrame(
      seed: userId.hashCode,
      badgeColor: badgeColor,
      child: avatar,
    );
  }
}

/// 劇画スタイルのアイコン枠。手描き風のギザギザした色付きブロック
/// （身だしなみのイメージカラーで塗る）の上に、白いリングで囲んだ
/// アバターを重ねる（2026-07-29追加、ユーザー提供の参考画像・手書き
/// スケッチを基に実装）。
class _GekigaAvatarFrame extends StatelessWidget {
  const _GekigaAvatarFrame({
    required this.child,
    required this.badgeColor,
    required this.seed,
  });

  final Widget child;
  final Color badgeColor;
  final int seed;

  @override
  Widget build(BuildContext context) {
    // 56×56の箱に対し、アバターは右上にわずかにはみ出す形で重ねる。
    // 参考スケッチのように色ブロックは正方形寄りの大きめのサイズにし、
    // 左下に色ブロックの表示面積が確保されるよう、アバターを右上へ寄せる
    // （2026-07-29再修正、色ブロックの形・大きさをスケッチに合わせ直した）。
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GekigaBadgePainter(color: badgeColor, seed: seed),
            ),
          ),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 劇画スタイルの色付きバッジ（アイコン背後のブロック）を描く。
/// 参考スケッチの形（正方形ではなく、左上に鋭い頂点・右側に大きく
/// 張り出す頂点・下に底の頂点・左に頂点を持つ、旗/凧のような非対称の
/// 四角形）を直線の辺でなぞり、外側から黒い太枠→白い縁取り→イメージ
/// カラーの塗り、という3層の同心図形として描く（2026-07-30再修正）。
/// 凸四角形にしているのは、[_insetPolygon]の辺オフセット計算が凹んだ
/// 頂点があると縁の太さが不均一・破綻しやすいため（前回、頂点を1つ
/// 内側に窪ませて凹四角形にした結果、白い縁取りがほぼ潰れて見えなく
/// なる不具合が発生した）。
class _GekigaBadgePainter extends CustomPainter {
  const _GekigaBadgePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = [
      Offset(size.width * 0.05, size.height * 0.03),
      Offset(size.width * 0.97, size.height * 0.42),
      Offset(size.width * 0.55, size.height * 0.98),
      Offset(size.width * 0.0, size.height * 0.55),
    ];
    final white = _insetPolygon(outer, 4.5);
    final fill = _insetPolygon(outer, 8);

    canvas.drawPath(_pathFromPoints(outer), Paint()..color = Colors.black);
    canvas.drawPath(_pathFromPoints(white), Paint()..color = Colors.white);
    canvas.drawPath(_pathFromPoints(fill), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GekigaBadgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// [vertices]の多角形の各辺を内側へ[inset]だけ平行移動し、隣り合う辺の
/// 交点を新しい頂点として返す（同心の縁取り・塗りを重ねて描くための
/// 下ごしらえ）。重心方向へ頂点を縮める単純な方式だと、辺の向きによって
/// 縁の太さがバラついたり凹み部分で図形が破綻したりするため、辺単位の
/// 平行移動＋交点計算という、太さが均一になる正しいオフセット処理にして
/// いる。
List<Offset> _insetPolygon(List<Offset> vertices, double inset) {
  final n = vertices.length;
  final centroid = vertices.reduce((a, b) => a + b) / n.toDouble();
  final origins = <Offset>[];
  final dirs = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % n];
    final edge = b - a;
    final dir = edge / edge.distance;
    var normal = Offset(-dir.dy, dir.dx);
    final mid = (a + b) / 2;
    final towardCentroid = centroid - mid;
    if (towardCentroid.dx * normal.dx + towardCentroid.dy * normal.dy < 0) {
      normal = -normal;
    }
    origins.add(a + normal * inset);
    dirs.add(dir);
  }
  final result = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = (i - 1 + n) % n;
    final p1 = origins[prev];
    final d1 = dirs[prev];
    final p2 = origins[i];
    final d2 = dirs[i];
    final denom = d1.dx * d2.dy - d1.dy * d2.dx;
    if (denom.abs() < 1e-6) {
      result.add(p2);
      continue;
    }
    final diff = p2 - p1;
    final t = (diff.dx * d2.dy - diff.dy * d2.dx) / denom;
    result.add(p1 + d1 * t);
  }
  return result;
}

Path _pathFromPoints(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// 劇画スタイルの吹き出し本体。手描き風ギザギザ枠線・モノクロの中身
/// （2026-07-29追加）。自分は白地に黒枠線、相手は黒地に白枠線で白黒反転する
/// （2026-07-29修正、参考画像の確認により相手側を黒背景・白文字に変更）。
class _GekigaBubble extends StatelessWidget {
  const _GekigaBubble({
    required this.child,
    required this.seed,
    required this.isMe,
  });

  final Widget child;
  final int seed;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GekigaBubblePainter(seed: seed, isMe: isMe),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: child,
      ),
    );
  }
}

class _GekigaBubblePainter extends CustomPainter {
  const _GekigaBubblePainter({required this.seed, required this.isMe});

  final int seed;
  final bool isMe;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _handDrawnPolygonPath(
      [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ],
      seed,
      jitter: 3.2,
      segmentsPerEdge: 5,
    );
    final fillColor = isMe ? Colors.white : Colors.black;
    final strokeColor = isMe ? Colors.black : Colors.white;
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GekigaBubblePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.isMe != isMe;
}

/// [vertices]で囲まれた多角形の各辺を、手描き風に少しだけジグザグに揺らした
/// 閉じたPathを作る。[seed]が同じなら常に同じ形になる（メッセージID・
/// ユーザーIDのhashCodeを渡すことで、再描画のたびに形がガタつかないように
/// している）。
Path _handDrawnPolygonPath(
  List<Offset> vertices,
  int seed, {
  double jitter = 3,
  int segmentsPerEdge = 4,
}) {
  final random = math.Random(seed);
  final points = <Offset>[];
  for (var i = 0; i < vertices.length; i++) {
    final from = vertices[i];
    final to = vertices[(i + 1) % vertices.length];
    for (var s = 1; s <= segmentsPerEdge; s++) {
      final t = s / segmentsPerEdge;
      final base = Offset.lerp(from, to, t)!;
      points.add(
        Offset(
          base.dx + (random.nextDouble() - 0.5) * 2 * jitter,
          base.dy + (random.nextDouble() - 0.5) * 2 * jitter,
        ),
      );
    }
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}
