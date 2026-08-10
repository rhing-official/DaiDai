import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderRepaintBoundary, SelectedContent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';
import '../../widgets/gekiga/monochrome_box.dart';
import 'attachment_popup_button.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/drag_menu_geometry.dart';
import '../../utils/link_detection.dart';
import '../../utils/message_time.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_photo_frame.dart';
import '../../widgets/link_preview_card.dart';
import '../../widgets/linkified_text.dart';
import '../../widgets/swipe_gestures.dart' show kSwipeGestureVelocityThreshold;

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
    this.onSendAttachment,
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
    this.roomTabBar,
    this.disabled = false,
    this.onSwipeBack,
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
  final Future<void> Function(String content, {bool silent, Message? replyTo})
  onSend;

  /// ファイル・画像・動画を添付したメッセージを送信する（技術仕様書5.6参照、
  /// 2026-08-10追加）。nullなら＋ボタン自体を表示しない（承認待ちの一対・
  /// 広場を開いた際の`disabled`なプレースホルダー画面など）。
  final Future<void> Function(PickedAttachment attachment)? onSendAttachment;

  /// 送信済みテキストメッセージの本文を編集する。nullなら編集機能自体を
  /// 提供しない（メニューに「編集」項目を出さない）。
  final Future<void> Function(String messageId, String newContent)?
  onEditMessage;

  /// 送信済みメッセージの送信取り消し（相手側にも痕跡を残さず完全に削除）。
  /// nullなら送信取り消し機能自体を提供しない。
  final Future<void> Function(String messageId)? onUnsendMessage;

  /// メッセージへの自分のリアクションを、呼び出し側が計算済みの完全な
  /// 絵文字リストで上書きする（空リストなら解除）。nullならリアクション
  /// 機能自体を提供しない。
  final Future<void> Function(String messageId, List<String> emojis)?
  onSetReaction;

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

  /// 狭い画面（縦表示）で、AppBarの直下に寄合の横スクロールタブバー
  /// （`RoomTabBar`）を表示する（2026-08-03追加）。単一モードの会話・
  /// 広い画面のサイドバー使用中（`TalksTab`の分割表示）ではnullのまま渡す。
  final PreferredSizeWidget? roomTabBar;

  /// trueの場合、入力欄をグレーアウトして操作不能にする（承認待ちの
  /// 一対・広場を開いたときなど、実際には送信・既読取得ができない状態を
  /// 見せるため、2026-08-05追加）。
  final bool disabled;

  /// 縦表示のチャット画面で、メッセージ吹き出しの上を右スワイプした時に
  /// 会話一覧へ戻る処理（2026-08-06追加）。吹き出し自体が横ドラッグを
  /// ジェスチャーアリーナ上で先に受理してしまい、外側の`SwipeBackDetector`
  /// （吹き出しの無い余白では機能する）に伝播しないため、`_MessageInteractions`
  /// 側に直接組み込む必要がある。広い画面の分割表示（`TalksTab`に埋め込み）
  /// では「会話一覧へ戻る」概念が無いため、呼び出し元はnullのまま渡す。
  final VoidCallback? onSwipeBack;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();

  /// メッセージ一覧のスクロール位置を、自動スクロール機能から直接操作する
  /// ために持つ（返信先ジャンプ機能は従来通りcontextベースの
  /// `Scrollable.ensureVisible`を使うため、この`controller`を必要としない）。
  final _scrollController = ScrollController();

  /// 自動スクロール開始位置（画面座標）を表示するアイコンの位置計算に使う。
  final _autoScrollAreaKey = GlobalKey();

  /// 入力欄オーバーレイ（返信/編集バー＋テキスト入力欄、build()末尾で
  /// メッセージ一覧の上に重ねて表示する）の実際の高さ計測用。メッセージ
  /// 一覧の下部余白をこの高さに追従させることで、入力欄の裏に完全に
  /// 隠れて見えなくなるメッセージが出ないようにしつつ、入力欄が伸び縮み
  /// する瞬間はメッセージがその下に滑らかに潜り込むように見せる
  /// （2026-07-30、入力欄の直前でメッセージが唐突に途切れて見える不具合の修正）。
  final _composerAreaKey = GlobalKey();
  double _composerAreaHeight = 72;

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

  /// [_composerAreaKey]が指す入力欄オーバーレイの実際の描画高さを計測し、
  /// [_composerAreaHeight]（メッセージ一覧の下部余白に使う）へ反映する。
  /// テキスト入力欄が複数行になる、返信/編集バーの表示が切り替わるなど
  /// 高さが変わるたびに呼び直す必要があるため、build()から毎フレーム後に
  /// スケジュールする。
  void _measureComposerArea() {
    if (!mounted) return;
    final box =
        _composerAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if ((height - _composerAreaHeight).abs() > 0.5) {
      setState(() => _composerAreaHeight = height);
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
        (elapsed - _autoScrollLastTick).inMicroseconds /
        Duration.microsecondsPerSecond;
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
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(next);
  }

  /// 既に既読リクエストを送った（または送信中の）メッセージIDの集合。
  /// Firestoreからの再送信のたびに同じメッセージへ既読を送り直さないための重複防止。
  final _markedReadIds = <String>{};

  /// メッセージの削除用・範囲選択モード。1件を長押しして「メッセージを削除」
  /// を選ぶと入り、以降はタップで選択のオン/オフを切り替える（連続していない
  /// 複数選択も可能）。スクリーンショット機能（[_screenshotSelecting]）とは
  /// 別モードで、同時には成立しない（2026-08-09、当初は同じ状態を共有する
  /// 実装だったが、削除は「バラバラに複数選択」・スクリーンショットは
  /// 「区間選択」と選び方の性質が違うため分離した）。
  bool _selecting = false;
  final _selectedMessageIds = <String>{};

  /// スクリーンショット用の範囲選択モード中かどうか（2026-08-09追加）。
  /// [_selecting]（削除用）とは独立した状態。タップの付け外しは
  /// [_selectedMessageIds]と全く同じトグル方式（[_toggleScreenshotSelected]）
  /// だが、実際にハイライト・撮影対象になるのは[_screenshotEffectiveIds]で
  /// 「選択済みの最古〜最新の間を全て埋めた」区間（2026-08-09、当初は
  /// 起点・終点の2点だけを保持する方式だったが、同じメッセージを再タップ
  /// しても値が変わらず「チェックを外せない」ように見える不具合があった
  /// ため、削除機能と同じ可逆的なトグル方式に変更した）。
  bool _screenshotSelecting = false;
  final _screenshotSelectedIds = <String>{};

  /// 文言コピー用に、現在「本文が選択可能」になっているメッセージ1件の
  /// ID（2026-08-09追加）。削除・スクリーンショットは複数メッセージの
  /// 選択だが、コピーは長押しした1件の本文中の一部を選ぶ機能のため、
  /// `Set`ではなく単一のnullableフィールドで持つ。
  String? _textCopyMessageId;

  /// [_textCopyMessageId]がセットされている間、その[SelectionArea]の
  /// Stateへアクセスして全文選択（[SelectableRegionState.selectAll]）や
  /// トースバー非表示（[SelectableRegionState.hideToolbar]）を呼ぶために
  /// 使う（2026-08-09追加）。1件しか同時に成立しないため使い回しでよい。
  final _partialCopyKey = GlobalKey<SelectionAreaState>();

  /// [_textCopyMessageId]の[SelectionArea.onSelectionChanged]から更新される、
  /// 現在の選択内容のキャッシュ（2026-08-09追加）。コピーボタン/Ctrl+C押下時に
  /// ここから文字列を取り出す（`setState`不要、`_cachedMessages`と同じ
  /// パターン）。
  SelectedContent? _partialCopySelectedContent;

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

  /// 直近のStreamBuilderスナップショット（新しい順）のキャッシュ。
  /// スクリーンショット機能は、選択後にダイアログでのユーザー確認を挟んで
  /// から実際のキャプチャを行うため、選択した時点のローカル変数
  /// （combined/messagesById）ではなく、常に最新化されるこのキャッシュから
  /// Messageを引く（2026-08-09追加）。`_extraMessages`と同じく、build()内で
  /// setStateを介さず直接更新する（このフィールド自体は再描画のトリガーに
  /// する必要が無いため）。
  List<Message> _cachedMessages = [];

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
      // 削除用の選択とスクリーンショット用の範囲選択・コピー用の文言選択は
      // 別モードのため、どれか1つに入ったら他は必ず抜ける（同時には成立
      // しない）。
      _screenshotSelecting = false;
      _screenshotSelectedIds.clear();
      _textCopyMessageId = null;
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

  /// スクリーンショット用の範囲選択モードに入る。削除用の複数選択とは
  /// 別モードで、長押しした1件を選択済みにして開始する（2026-08-09、
  /// 削除機能との混同を避けるためユーザー指摘を受けて分離）。
  void _enterScreenshotSelection(String messageId) {
    setState(() {
      _screenshotSelecting = true;
      _screenshotSelectedIds
        ..clear()
        ..add(messageId);
      // 削除用の選択モード・コピー用の文言選択モードと同時には成立しない。
      _selecting = false;
      _selectedMessageIds.clear();
      _textCopyMessageId = null;
    });
  }

  /// 部分コピー用の文言選択モードに入る。長押しメニューの「部分コピー」
  /// から呼ばれる（2026-08-09、メッセージへの直接コピー＝ホバーでの入り口は
  /// 廃止し、メニュー経由のみに変更）。削除・スクリーンショットのような
  /// 複数メッセージ選択ではなく、[messageId]1件だけの本文を選択可能
  /// （[SelectionArea]）にし、入った直後は全文が選択済みの状態から
  /// スタートする（カーソルでコピーしたい範囲だけに絞り込める）。終了は
  /// 明示的な×ボタンではなく、コピー操作（Ctrl+C／選択ツールバーの
  /// 「コピー」）をした時点で自動的に行う（[_copyPartialSelectionAndExit]
  /// 参照、2026-08-09変更）。
  void _enterTextCopyMode(String messageId) {
    setState(() {
      _textCopyMessageId = messageId;
      _selecting = false;
      _selectedMessageIds.clear();
      _screenshotSelecting = false;
      _screenshotSelectedIds.clear();
      _partialCopySelectedContent = null;
    });
    // web(DDC)ではSelectionAreaのマウント・レイアウトが1フレームで
    // 完了しないことがある（スクリーンショット撮影のtoImage()と同じ
    // 事情）ため、2フレーム待ってから全文選択する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _partialCopyKey.currentState?.selectableRegion.selectAll();
      });
    });
  }

  void _exitTextCopyMode() {
    setState(() {
      _textCopyMessageId = null;
      _partialCopySelectedContent = null;
    });
  }

  /// 部分コピーモード中に、選択済みの文字列をクリップボードへコピーして
  /// モードを終了する（Ctrl+C・選択ツールバーの「コピー」ボタン双方から
  /// 呼ばれる共通処理、2026-08-09追加）。
  void _copyPartialSelectionAndExit() {
    final text = _partialCopySelectedContent?.plainText;
    if (text != null && text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
    }
    _partialCopyKey.currentState?.selectableRegion.hideToolbar();
    _exitTextCopyMode();
  }

  /// 長押しメニューの「コピー」。選択操作を挟まず、メッセージ本文全体を
  /// 即座にクリップボードへコピーする（2026-08-09、部分コピーとは別の
  /// 即時実行アクション）。
  Future<void> _copyMessageText(Message message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(appStringsProvider).chatCopiedMessage)),
    );
  }

  /// 現在の実効範囲（[_screenshotEffectiveIds]）に含まれるメッセージを
  /// クリックした場合は、時系列でそれより後ろ（新しい側）を全て解除する
  /// （「上にあるメッセージを優先する」、2026-08-09変更）。例:
  /// 1〜3件目を選択中に2件目をクリック→1件目だけ残る。範囲外のメッセージを
  /// クリックした場合はこれまで通り追加し、[_screenshotEffectiveIds]の
  /// 穴埋めで範囲が広がる。
  void _toggleScreenshotSelected(String messageId) {
    setState(() {
      final chronological = [..._cachedMessages]
        ..sort((a, b) {
          final aTime = a.sentAt?.toDate() ?? DateTime.now();
          final bTime = b.sentAt?.toDate() ?? DateTime.now();
          return aTime.compareTo(bTime);
        });
      final effective = _screenshotEffectiveIds(chronological);
      if (effective.contains(messageId)) {
        final idx = chronological.indexWhere((m) => m.messageId == messageId);
        final lo = chronological.indexWhere(
          (m) => effective.contains(m.messageId),
        );
        if (idx == lo) {
          _screenshotSelectedIds.clear();
        } else {
          _screenshotSelectedIds
            ..clear()
            ..addAll(chronological.sublist(lo, idx).map((m) => m.messageId));
        }
      } else {
        _screenshotSelectedIds.add(messageId);
      }
    });
  }

  void _exitScreenshotSelection() {
    setState(() {
      _screenshotSelecting = false;
      _screenshotSelectedIds.clear();
    });
  }

  /// [_screenshotSelectedIds]に含まれるメッセージのうち、[orderedMessages]
  /// （新しい順・古い順どちらでもよい）上で最も古い位置〜最も新しい位置の
  /// 間を全て埋めて返す（「1件目・3件目を選ぶと2件目も自動的に選択される」
  /// という区間選択の実体。実際にトグルされる[_screenshotSelectedIds]自体は
  /// 個別にon/off可能な集合のままにして、表示・撮影対象の算出にのみ
  /// この穴埋めを適用する、2026-08-09変更）。
  Set<String> _screenshotEffectiveIds(List<Message> orderedMessages) {
    if (_screenshotSelectedIds.isEmpty) return const {};
    var lo = -1;
    var hi = -1;
    for (var i = 0; i < orderedMessages.length; i++) {
      if (!_screenshotSelectedIds.contains(orderedMessages[i].messageId)) {
        continue;
      }
      if (lo == -1) lo = i;
      hi = i;
    }
    if (lo == -1) return {..._screenshotSelectedIds};
    return {for (var i = lo; i <= hi; i++) orderedMessages[i].messageId};
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

  /// 選択した範囲のスクリーンショットを作成する前に、「呼び名にぼかしを
  /// 入れる」チェックボックス付きの確認ダイアログを出す（2026-08-09追加）。
  /// キャンセルした場合は範囲選択モードを維持する（削除と異なり、選び直す
  /// 余地を残すため即座に[_exitScreenshotSelection]しない）。
  Future<void> _confirmScreenshotSelected() async {
    final strings = ref.read(appStringsProvider);
    var blur = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => CallbackShortcuts(
          // Enterキーで「撮影する」を実行できるようにする（2026-08-09追加）。
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () =>
                Navigator.of(context).pop(true),
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: Text(strings.chatScreenshotDialogTitle),
              content: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: blur,
                title: Text(strings.chatScreenshotBlurCheckboxLabel),
                onChanged: (value) =>
                    setDialogState(() => blur = value ?? false),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(strings.chatScreenshotConfirmButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final ids = _screenshotEffectiveIds(_cachedMessages).toList();
    _exitScreenshotSelection();
    await _captureAndShareScreenshot(ids, blurSenderInfo: blur);
  }

  /// [ids]に対応するメッセージだけをオフスクリーンに組み立てて画像化し、
  /// 共有シート（[SharePlus]）へ渡す（2026-08-09追加）。選択は連続していなく
  /// てもよいため、表示中のビューポートをそのまま撮影するのではなく、
  /// 選択分だけを別のウィジェットツリーとして`Overlay`上に組み立てて
  /// キャプチャする（`Offstage`は`offstage:true`の間`paint`自体を行わない
  /// ため、`RepaintBoundary.toImage()`用のレイヤーが作られず使えない）。
  Future<void> _captureAndShareScreenshot(
    List<String> ids, {
    required bool blurSenderInfo,
  }) async {
    final strings = ref.read(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final floatingShadow =
        Theme.of(context).extension<AppThemeExtras>()?.floatingShadow ??
        AppThemeExtras.none;
    final uiStyle = ref.read(appUiStyleProvider);
    final layoutStyle = ref.read(chatLayoutStyleProvider);
    final timeFormat = ref.read(messageTimeFormatProvider);
    final locale = ref.read(appLocaleProvider);
    final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final chatAreaWidth =
        (_autoScrollAreaKey.currentContext?.findRenderObject() as RenderBox?)
            ?.size
            .width ??
        MediaQuery.sizeOf(context).width;

    final idSet = ids.toSet();
    final selected =
        _cachedMessages.where((m) => idSet.contains(m.messageId)).toList()
          ..sort((a, b) {
            final aTime = a.sentAt?.toDate() ?? DateTime.now();
            final bTime = b.sentAt?.toDate() ?? DateTime.now();
            return aTime.compareTo(bTime);
          });
    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.chatScreenshotErrorMessage)),
      );
      return;
    }
    final messagesById = {for (final m in _cachedMessages) m.messageId: m};

    // アイコン画像は_MessageRowが内部で非同期に読み込むため、キャプチャ前に
    // 事前読み込みしておかないと空欄のまま撮影されてしまう可能性がある。
    // 1件failしても他のアイコンの撮影を妨げないよう個別にcatchする。
    final iconUrls = <String>{};
    for (final m in selected) {
      final url = ref
          .read(watchedUserProvider(m.senderId))
          .value
          ?.effectiveIconFor(widget.conversationId)
          ?.url;
      if (url != null) iconUrls.add(url);
    }
    if (!mounted) return;
    await Future.wait(
      iconUrls.map(
        (url) => precacheImage(NetworkImage(url), context).catchError((_) {}),
      ),
    );
    if (!mounted) return;

    final rows = <Widget>[];
    DateTime? currentDay;
    for (final message in selected) {
      final sentAt = message.sentAt?.toDate();
      if (sentAt != null &&
          (currentDay == null || !isSameDay(sentAt, currentDay))) {
        currentDay = sentAt;
        rows.add(
          _DateSeparator(
            date: sentAt,
            locale: locale,
            isGekiga: uiStyle == AppUiStyle.gekiga,
          ),
        );
      }
      rows.add(
        _MessageRow(
          key: ValueKey('capture_${message.messageId}'),
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
          senderNameColorResolver: widget.senderNameColorResolver,
          blurSenderInfo: blurSenderInfo,
          messagesById: messagesById,
          timeFormat: timeFormat,
        ),
      );
    }

    final captureKey = GlobalKey();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      // Web(CanvasKit)では極端に画面外（大きな負の座標）へ置いた
      // RepaintBoundaryがtoImage()で正しく描画されない不具合があるため、
      // 実座標としては画面左上（0,0）に置いた上でClipRectで見た目上0x0に
      // 畳んで隠す（ClipRectによる祖先側のクリップはRepaintBoundary自身の
      // 独立したレイヤーには影響しないため、toImage()側は全体を正しく
      // キャプチャできる、2026-08-09変更）。
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: ClipRect(
          child: Material(
            type: MaterialType.transparency,
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: captureKey,
                child: ColoredBox(
                  color: scaffoldBackground,
                  child: SizedBox(
                    width: chatAreaWidth,
                    // 通常のメッセージ一覧（ListView）が持つ12pxの余白を
                    // 再現する。これが無いとアイコンの左上突き出し部分
                    // （GekigaPhotoFrameのoverflow）が撮影範囲の外に出て
                    // 左端が欠けて見える（2026-08-09追加）。
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: rows,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Uint8List? pngBytes;
    try {
      // ネットワーク画像・レイアウトが確実に反映されるよう2フレーム待つ。
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: devicePixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) throw StateError('toByteData returned null');
    } catch (e, st) {
      // web-serverターゲットではflutter runのターミナルへdebugPrintが
      // 転送されないため、ブラウザのDevToolsコンソールでも確認できるよう
      // 残しておく（2026-08-09追加）。
      debugPrint('スクリーンショットのキャプチャに失敗: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.chatScreenshotErrorMessage)),
        );
      }
      return;
    } finally {
      entry.remove();
    }
    try {
      final fileName =
          'daidai_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('スクリーンショットの共有に失敗: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.chatScreenshotErrorMessage)),
        );
      }
    }
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

  Future<void> _send({bool silent = false}) async {
    if (widget.disabled) return;
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

  /// ＋ボタンで選んだ添付を送信する（技術仕様書5.5・5.6参照、2026-08-10追加）。
  /// 失敗時はエラー内容に応じたバナーを画面上部に3秒程度表示する
  /// （2026-08-10変更、以前はSnackBarで自動的に消えるまでの時間が
  /// 分かりにくく、連続失敗時に表示され続けているように見えていたため。
  /// `MaterialBanner`はSnackBarと違いキューイングされず常に最新の1件だけが
  /// 表示される）。自動リトライ・レジュームは行わず、再送はバナーの
  /// 「再送」アクションから同じ添付を渡してもう一度呼び直す形にする。
  Future<void> _handleAttachmentPicked(PickedAttachment attachment) async {
    final onSendAttachment = widget.onSendAttachment;
    if (onSendAttachment == null) return;
    try {
      await onSendAttachment(attachment);
    } catch (e) {
      if (!mounted) return;
      final strings = ref.read(appStringsProvider);
      final message = switch (e) {
        AttachmentTooLargeException() => strings.chatAttachmentTooLargeMessage,
        AttachmentExtensionBlockedException() =>
          strings.chatAttachmentBlockedExtensionMessage,
        _ => strings.chatAttachmentSendFailedMessage,
      };
      final messenger = ScaffoldMessenger.of(context);
      final canResend =
          e is! AttachmentTooLargeException &&
          e is! AttachmentExtensionBlockedException;
      _attachmentBannerTimer?.cancel();
      messenger
        ..clearMaterialBanners()
        ..showMaterialBanner(
          MaterialBanner(
            content: Text(message),
            actions: [
              if (canResend)
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentMaterialBanner();
                    _handleAttachmentPicked(attachment);
                  },
                  child: Text(strings.chatResendAction),
                )
              else
                TextButton(
                  onPressed: messenger.hideCurrentMaterialBanner,
                  child: Text(strings.cancel),
                ),
            ],
          ),
        );
      _attachmentBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) messenger.hideCurrentMaterialBanner();
      });
    }
  }

  /// メッセージ入力欄でのEnterキー処理。設定（[SendKeyMode]）に応じて、
  /// 送信・相手に通知しない送信・改行のどれを行うかを自前で判定する。
  /// TextFieldの既定のEnter処理（ハードウェアキーボードからの生キーイベントに
  /// 対しては、プラットフォームのIME経由の改行挿入が常に走るとは限らない）に
  /// 依存すると環境によって改行が入らないことがあったため、改行も自前で挿入する。
  ///
  /// Android/iOS（モバイル）はソフトウェアキーボードにShiftキーが無く
  /// Shift+Enterによる改行ができない上、機種・IMEによっては改行キーを
  /// 押しただけで生のEnterキーイベントが飛んでくることがあり、送信キー設定に
  /// 応じた判定をそのまま適用すると誤って送信されてしまう（実機で報告された
  /// 不具合）。そのため、モバイルでは[SendKeyMode]の設定に関わらずEnterは
  /// 常に改行のみとし、送信は送信ボタンのタップに固定する。
  ///
  /// キー割り当て（Windows/Linux/macOS等、物理キーボード前提の環境のみ）:
  /// - Enterで送信モード: Enter=送信 / Shift+Enter=改行 / Ctrl+Enter=通知せず送信
  /// - Ctrl+Enterで送信モード: Enter=改行 / Ctrl+Enter=送信 / Ctrl+Shift+Enter=通知せず送信
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _insertNewline();
      return KeyEventResult.handled;
    }

    final mode = ref.read(sendKeyModeProvider);
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final ctrlPressed =
        HardwareKeyboard.instance.isControlPressed ||
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

  /// 添付送信失敗バナー（`_handleAttachmentPicked`）を3秒後に自動的に
  /// 閉じるためのタイマー（2026-08-10追加）。
  Timer? _attachmentBannerTimer;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _autoScrollTicker?.dispose();
    _attachmentBannerTimer?.cancel();
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
    // 劇画UIの背景色はユーザーが設定タブから編集可能（gekigaBackgroundColorProvider、
    // 2026-08-05）なため、固定値を決め打ちせずTheme経由で参照する
    // （どちらのスタイルでもTheme側の値が既に正しいため、isGekigaでの
    // 分岐自体が不要になった）。
    final composerBackground = Theme.of(context).scaffoldBackgroundColor;

    // 入力欄オーバーレイの高さは行数や返信/編集バーの有無で変わるため、
    // 毎フレーム後に実測してメッセージ一覧の下部余白へ反映する
    // （_measureComposerAreaのコメント参照）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureComposerArea());

    return Scaffold(
      appBar: AppBar(
        foregroundColor: isGekiga ? Colors.white : null,
        automaticallyImplyLeading: false,
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : _screenshotSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitScreenshotSelection,
              )
            : null,
        // 寄合名（widget.title）は、広い画面ではRoomListPaneのタブ、狭い
        // 画面ではRoomTabBarに既に表示されており冗長なため、劇画スタイル
        // では非表示にする（2026-08-04追加。選択モード中の「n件選択中」
        // 表示は別物なので維持する。シンプルスタイルは現状通り表示）。
        title: _selecting
            ? Text(strings.chatSelectionModeTitle(_selectedMessageIds.length))
            : _screenshotSelecting
            ? Text(
                strings.chatScreenshotSelectionModeTitle(
                  _screenshotEffectiveIds(_cachedMessages).length,
                ),
              )
            : (isGekiga ? null : Text(widget.title)),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: strings.chatDeleteSelectedTooltip,
                  onPressed: _selectedMessageIds.isEmpty
                      ? null
                      : _confirmDeleteSelected,
                ),
              ]
            : _screenshotSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  tooltip: strings.chatScreenshotTooltip,
                  onPressed: _screenshotSelectedIds.isEmpty
                      ? null
                      : _confirmScreenshotSelected,
                ),
              ]
            : [
                if (widget.onCallPressed case final onCall?)
                  isGekiga
                      ? GekigaIconButton(
                          icon: Icons.call_outlined,
                          onPressed: onCall,
                        )
                      : IconButton(
                          icon: const Icon(Icons.call_outlined),
                          onPressed: onCall,
                        ),
                if (widget.onVideoCallPressed case final onVideoCall?)
                  isGekiga
                      ? GekigaIconButton(
                          icon: Icons.videocam_outlined,
                          onPressed: onVideoCall,
                        )
                      : IconButton(
                          icon: const Icon(Icons.videocam_outlined),
                          onPressed: onVideoCall,
                        ),
                ...?widget.extraActions,
              ],
        bottom: widget.roomTabBar,
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
                        return Padding(
                          padding: EdgeInsets.only(bottom: _composerAreaHeight),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: _composerAreaHeight),
                          child: Center(child: Text('エラー: ${snapshot.error}')),
                        );
                      }
                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: _composerAreaHeight),
                          child: const Center(child: Text('まだメッセージはありません')),
                        );
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
                      final combined = [...messages, ..._extraMessages.values]
                        ..sort((a, b) {
                          final aTime = a.sentAt?.toDate() ?? DateTime.now();
                          final bTime = b.sentAt?.toDate() ?? DateTime.now();
                          return bTime.compareTo(aTime);
                        });
                      _cachedMessages = combined;

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
                      _messageKeys.removeWhere(
                        (id, _) => !currentIds.contains(id),
                      );

                      // combinedは新しい順（index 0が最新）。日付区切りを「その日の
                      // 最初のメッセージの直上」に挿入したいので、一旦古い順に走査して
                      // 区切り込みのリストを組み立ててから反転する。reverse:trueの
                      // ListViewにそのまま渡すと、index 0（リストの末尾＝一番新しい
                      // 要素）が画面下端に来て、見た目は上から古い順（区切り→その日の
                      // メッセージ…）に正しく並ぶ。
                      final screenshotEffectiveIds = _screenshotSelecting
                          ? _screenshotEffectiveIds(combined)
                          : const <String>{};

                      final entries = <Widget>[];
                      DateTime? currentDay;
                      for (var i = combined.length - 1; i >= 0; i--) {
                        final message = combined[i];
                        final sentAt = message.sentAt?.toDate();
                        if (sentAt != null &&
                            (currentDay == null ||
                                !isSameDay(sentAt, currentDay))) {
                          currentDay = sentAt;
                          entries.add(
                            _DateSeparator(
                              date: sentAt,
                              locale: locale,
                              isGekiga: isGekiga,
                            ),
                          );
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
                            onSenderTap: (_selecting || _screenshotSelecting)
                                ? null
                                : widget.onSenderTap,
                            senderNameColorResolver:
                                widget.senderNameColorResolver,
                            selecting: _selecting || _screenshotSelecting,
                            selected: _selecting
                                ? _selectedMessageIds.contains(
                                    message.messageId,
                                  )
                                : screenshotEffectiveIds.contains(
                                    message.messageId,
                                  ),
                            canSelect: widget.onHideMessages != null,
                            onEnterSelection: _enterSelectionMode,
                            onEnterScreenshotSelection:
                                _enterScreenshotSelection,
                            textCopySelecting:
                                _textCopyMessageId == message.messageId,
                            onEnterTextCopy: _enterTextCopyMode,
                            partialCopySelectionKey: _partialCopyKey,
                            onPartialCopySelectionChanged: (content) =>
                                _partialCopySelectedContent = content,
                            onCopyPartialSelection:
                                _copyPartialSelectionAndExit,
                            onCopyMessage: _copyMessageText,
                            onToggleSelected: _selecting
                                ? _toggleSelected
                                : (_screenshotSelecting
                                      ? _toggleScreenshotSelected
                                      : null),
                            messagesById: messagesById,
                            onReply: _startReply,
                            onEdit: widget.onEditMessage != null
                                ? _startEdit
                                : null,
                            onUnsend: widget.onUnsendMessage,
                            onSetReaction: widget.onSetReaction,
                            onJumpToReply: _jumpToMessage,
                            highlighted:
                                _highlightedMessageId == message.messageId,
                            timeFormat: timeFormat,
                            onDeclineAccountDeletionNotice:
                                widget.onDeclineAccountDeletionNotice,
                            onDeleteAfterAccountDeletion:
                                widget.onDeleteAfterAccountDeletion,
                            onAutoScrollStart:
                                (_selecting || _screenshotSelecting)
                                ? null
                                : _startAutoScroll,
                            onAutoScrollUpdate:
                                (_selecting || _screenshotSelecting)
                                ? null
                                : _updateAutoScrollPosition,
                            onAutoScrollEnd:
                                (_selecting || _screenshotSelecting)
                                ? null
                                : _stopAutoScroll,
                            onSwipeBack: widget.onSwipeBack,
                          ),
                        );
                      }
                      final reversedEntries = entries.reversed.toList();

                      // 返信先ジャンプ機能（Scrollable.ensureVisible）は対象行が
                      // 既にツリー上にビルドされている必要があるため、遅延ビルドの
                      // ListView.builderではなく全件ビルド済みのListViewを使う
                      // （現在ロード済みメッセージは最新50件程度に収まる想定）。
                      //
                      // メッセージ一覧は入力欄の裏まで全画面分の高さで敷き、
                      // 入力欄自体はStack最前面のオーバーレイとして重ねる
                      // （下記Positioned参照）。下部余白（bottomInset）を
                      // 入力欄の実測高さに合わせてTweenAnimationBuilderで
                      // アニメーションさせることで、入力欄が伸び縮みする際に
                      // メッセージがその下へ滑らかに潜り込むように見せている
                      // （2026-07-30、入力欄の直前でメッセージが唐突に
                      // 途切れて見える不具合の修正）。
                      return TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          end: (_selecting || _screenshotSelecting)
                              ? 0
                              : _composerAreaHeight,
                        ),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        builder: (context, bottomInset, _) => ListView(
                          controller: _scrollController,
                          reverse: true,
                          padding: EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            12 + bottomInset,
                          ),
                          children: reversedEntries,
                        ),
                      );
                    },
                  ),
                ),
                if (_autoScrollOrigin != null) _buildAutoScrollIndicator(),
                if (!_selecting && !_screenshotSelecting)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      key: _composerAreaKey,
                      color: composerBackground,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_replyingTo != null || _editingMessage != null)
                            _ComposerContextBar(
                              replyingTo: _replyingTo,
                              editing: _editingMessage != null,
                              strings: strings,
                              onCancel: _cancelComposerContext,
                            ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Focus(
                                      onKeyEvent: _handleKeyEvent,
                                      child: isGekiga
                                          ? _GekigaComposerField(
                                              child: TextField(
                                                controller: _textController,
                                                enabled: !widget.disabled,
                                                minLines: 1,
                                                maxLines: 6,
                                                textInputAction:
                                                    TextInputAction.newline,
                                                keyboardType:
                                                    TextInputType.multiline,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                ),
                                                cursorColor: Colors.black,
                                                decoration: InputDecoration(
                                                  hintText:
                                                      strings.chatInputHint,
                                                  hintStyle: TextStyle(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.4),
                                                  ),
                                                  filled: false,
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                ),
                                              ),
                                            )
                                          : TextField(
                                              controller: _textController,
                                              enabled: !widget.disabled,
                                              minLines: 1,
                                              maxLines: 6,
                                              textInputAction:
                                                  TextInputAction.newline,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              decoration: InputDecoration(
                                                hintText: strings.chatInputHint,
                                                filled: widget.disabled,
                                                fillColor: Theme.of(context)
                                                    .disabledColor
                                                    .withValues(alpha: 0.08),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  // ＋ボタン（技術仕様書5.6参照）。TextFieldの
                                  // suffixIconとして持たせると、TextField自身が
                                  // 持つタップ検出（ジェスチャーアリーナに
                                  // 参加しない`Listener`ベースの独自実装と
                                  // 競合しない側）がこのタップも検出してしまい、
                                  // ソフトウェアキーボードが開いてポップアップの
                                  // 表示位置がズレる不具合があった。TextFieldの
                                  // 外（送信ボタンと同じRowの兄弟要素）に出すことで
                                  // 回避する（2026-08-10変更）。
                                  if (widget.onSendAttachment != null &&
                                      !widget.disabled)
                                    AttachmentPopupButton(
                                      strings: strings,
                                      isGekiga: isGekiga,
                                      onPicked: _handleAttachmentPicked,
                                    ),
                                  // 物理キーボード接続の判定に関わらず、何か入力されている間は
                                  // 常に送信ボタンを表示する（判定を誤っても送信手段が
                                  // 無くならないようにするため）。disabled時は入力自体が
                                  // できないため、送信ボタンも常に出さない。
                                  if (!widget.disabled)
                                    ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _textController,
                                      builder: (context, value, _) {
                                        if (value.text.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return Material(
                                          color: Colors.transparent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: _send,
                                            onLongPress: () =>
                                                _send(silent: true),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Icon(
                                                Icons.send,
                                                color: colorScheme.primary,
                                              ),
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
                    ),
                  ),
              ],
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
  const _DateSeparator({
    required this.date,
    required this.locale,
    required this.isGekiga,
  });

  final DateTime date;
  final AppLocale locale;
  final bool isGekiga;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isGekiga
                ? GekigaColors.panel
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            formatMessageDate(date, locale),
            style: TextStyle(
              fontSize: 12,
              color: isGekiga
                  ? GekigaColors.onPanel
                  : colorScheme.onSurfaceVariant,
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
    this.blurSenderInfo = false,
    this.selecting = false,
    this.selected = false,
    this.canSelect = false,
    this.onEnterSelection,
    this.onEnterScreenshotSelection,
    this.textCopySelecting = false,
    this.onEnterTextCopy,
    this.partialCopySelectionKey,
    this.onPartialCopySelectionChanged,
    this.onCopyPartialSelection,
    this.onCopyMessage,
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
    this.onSwipeBack,
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

  /// trueなら送信者のアイコン・呼び名をぼかして表示する（2026-08-09追加）。
  /// スクリーンショット機能でオフスクリーンに組み立てる複製行専用のオプション
  /// で、通常の画面表示（オンスクリーンの一覧）では常にfalseのまま渡される。
  final bool blurSenderInfo;

  /// 削除用の複数選択モード、またはスクリーンショット用の範囲選択モード
  /// （[onEnterScreenshotSelection]参照）中かどうか（[ChatScreen.onHideMessages]
  /// が渡されている場合のみ長押しで入れる）。
  final bool selecting;
  final bool selected;
  final bool canSelect;
  final void Function(String messageId)? onEnterSelection;

  /// スクリーンショット用の範囲選択モードに入る（[onEnterSelection]とは
  /// 別モード、2026-08-09追加）。
  final void Function(String messageId)? onEnterScreenshotSelection;

  /// このメッセージが部分コピー用の文言選択モード中かどうか（2026-08-09
  /// 追加）。削除・スクリーンショットと違い1件だけが対象になる。
  final bool textCopySelecting;

  /// 部分コピー用の文言選択モードに入る（長押しメニューの「部分コピー」
  /// から呼ばれる）。
  final void Function(String messageId)? onEnterTextCopy;

  /// [textCopySelecting]中の[SelectionArea]へアクセスするためのキー
  /// （入った直後に全文選択するため、2026-08-09追加）。
  final GlobalKey<SelectionAreaState>? partialCopySelectionKey;

  /// [textCopySelecting]中、選択内容が変わるたびに呼ばれる
  /// （2026-08-09追加、コピー実行時にここでキャッシュした文字列を使う）。
  final ValueChanged<SelectedContent?>? onPartialCopySelectionChanged;

  /// 部分コピーモード中に選択済みの文字列をコピーしてモードを終了する
  /// （Ctrl+C・選択ツールバーの「コピー」双方から呼ぶ、2026-08-09追加）。
  final VoidCallback? onCopyPartialSelection;

  /// 長押しメニューの「コピー」。選択操作を挟まず、メッセージ本文全体を
  /// 即座にクリップボードへコピーする（2026-08-09追加）。
  final void Function(Message message)? onCopyMessage;
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
  final void Function(String messageId, List<String> emojis)? onSetReaction;

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

  /// 縦表示で、吹き出しの上を右スワイプした時に会話一覧へ戻る処理
  /// ([ChatScreen.onSwipeBack]参照)。右寄せ表示（自分のメッセージ・
  /// sideBySideレイアウト）ではこの挙動を除外する
  /// （`_MessageInteractions`側で判定）。
  final VoidCallback? onSwipeBack;

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
        final left = badgeRect.left.clamp(8.0, screenSize.width - width - 8.0);
        final spaceBelow = screenSize.height - badgeRect.bottom;
        final showAbove =
            spaceBelow < minPopupSpace && badgeRect.top > spaceBelow;
        final top = showAbove ? null : badgeRect.bottom + 4;
        final bottom = showAbove ? screenSize.height - badgeRect.top + 4 : null;
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

  /// リアクション一覧ポップアップ（誰がどの絵文字を付けたか）。
  /// [_showReadReceiptPopup]と同じ位置決め・見た目のパターンを踏襲する
  /// （2026-08-05追加）。自分の行（`entry.key == currentUserId`）にのみ
  /// ゴミ箱ボタンを出し、押すと自分のリアクションを取り消してポップアップ
  /// を閉じる（一覧は静的表示のため、既読ポップアップと同様に取り消し後は
  /// 再度タップして開き直す想定）。
  void _showReactionListPopup(
    BuildContext context,
    BuildContext chipContext,
    Strings strings,
  ) {
    final chipBox = chipContext.findRenderObject()! as RenderBox;
    final chipRect = chipBox.localToGlobal(Offset.zero) & chipBox.size;
    const width = 240.0;
    const minPopupSpace = 160.0;
    // 1ユーザーが複数の異なる絵文字を持てるため、(userId, 絵文字)の
    // ペア単位にフラット化して1行ずつ表示する（2026-08-05変更）。
    final entries = <MapEntry<String, String>>[
      for (final e in message.reactions.entries)
        for (final emoji in e.value) MapEntry(e.key, emoji),
    ];

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenSize = MediaQuery.sizeOf(context);
        final left = chipRect.left.clamp(8.0, screenSize.width - width - 8.0);
        final spaceBelow = screenSize.height - chipRect.bottom;
        final showAbove =
            spaceBelow < minPopupSpace && chipRect.top > spaceBelow;
        final top = showAbove ? null : chipRect.bottom + 4;
        final bottom = showAbove ? screenSize.height - chipRect.top + 4 : null;
        final maxHeight = showAbove
            ? chipRect.top - 24
            : screenSize.height - chipRect.bottom - 24;
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
                          strings.reactionListPopupTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final isMine = entry.key == currentUserId;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  _SenderAvatar(
                                    userId: entry.key,
                                    rhingId: null,
                                    conversationId: conversationId,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SenderName(
                                      userId: entry.key,
                                      rhingId: null,
                                      conversationId: conversationId,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(entry.value),
                                  if (isMine)
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        final mine =
                                            message.reactions[currentUserId] ??
                                            [];
                                        onSetReaction?.call(
                                          message.messageId,
                                          mine
                                              .where((e) => e != entry.value)
                                              .toList(),
                                        );
                                        Navigator.of(context).pop();
                                      },
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
    final readers = message.readBy
        .where((r) => r.userId != message.senderId)
        .toList();
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
      final replySenderRhingId =
          target?.senderRhingId ?? message.replyToSenderRhingId;
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
    final isAttachment =
        message.contentType == 'file' ||
        message.contentType == 'image' ||
        message.contentType == 'video';

    final bubbleContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?replyPreview,
        if (isCallSummary)
          _callSummaryContent(onBubbleColor)
        else if (isAccountDeletedNotice)
          _accountDeletedContent(context, ref, strings, onBubbleColor)
        else if (isAttachment)
          _attachmentContent(context, onBubbleColor)
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
            alignRight: alignRight,
            child: bubbleContent,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: floatingShadow,
            ),
            child: bubbleContent,
          );

    // 既読バッジは吹き出しの横（バブルが右寄せの時は左横、左寄せの時は
    // 右横）に、吹き出しの下端を下限として並べる（2026-08-05変更）。
    // 以前はStack+Positionedで吹き出しの外へ重ねていたが、Positionedの
    // オーバーフロー分はStack自身のサイズに含まれず、(1)ListView側の
    // 行の高さに反映されない（次のメッセージと重なる）、(2)吹き出しの
    // サイズを超えた領域はヒットテストが届かずタップが効かない、という
    // 2つの不具合があったため、Rowで実際に横並びにするレイアウトへ
    // 変更した（bubbleをFlexibleにしてバッジ分の幅を確保する）。
    // テキストメッセージの自分の投稿のみ編集可能（画像等contentType='text'
    // 以外は将来実装時もまず本文編集の対象外という方針、Planでの検討通り）。
    final canEdit = isMe && message.contentType == 'text' && onEdit != null;

    // 劇画スタイルでは、ジグザグ枠にはせず色だけモノクロ（黒地白文字）に
    // 変える（2026-08-04追加。`colorScheme.surface`は劇画テーマだと背景と
    // 同じ赤になっており、そのままでは背景に溶け込んでほぼ見えなかった）。
    final readBadgeFg = isGekiga ? GekigaColors.onPanel : colorScheme.primary;
    final badgeContent = isSimpleDmReadMark
        ? Icon(Icons.done, size: 12, color: readBadgeFg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done, size: 12, color: readBadgeFg),
              const SizedBox(width: 2),
              Text(
                '${readers.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: readBadgeFg,
                ),
              ),
            ],
          );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isGekiga ? GekigaColors.panel : colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: floatingShadow,
      ),
      child: badgeContent,
    );

    final replyTargetId = message.replyToMessageId;
    final onBubbleTap = (replyTargetId != null && onJumpToReply != null)
        ? () => onJumpToReply!(replyTargetId)
        : null;

    final readBadge = showReadMark
        ? (isSimpleDmReadMark
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
                ))
        : null;
    final hasReactions = message.reactions.values.any(
      (emojis) => emojis.isNotEmpty,
    );

    // 長押し/右クリックでリアクション・返信・編集等のメニューを開く判定は
    // 吹き出し本体だけに絞る（2026-07-29変更）。以前は行全体（余白込み）が
    // 対象だったが、余白部分の長押しは自動スクロール（[_MessageInteractions]
    // 参照）に割り当てたため、両者が同じ操作を奪い合わないよう分離した。
    final bubbleWithReadMark = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          // 既読バッジは吹き出しの下端を下限として横に並べる
          // （バッジの方が低いものは無いが、万一同じ高さでも吹き出し側の
          // 下端に揃う）。
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (alignRight && readBadge != null) ...[
              readBadge,
              const SizedBox(width: 6),
            ],
            Flexible(
              // 部分コピーモード中は、ドラッグでの範囲選択・Ctrl+Cコピーを
              // SelectionAreaに任せるため、タップ/長押しを奪う
              // _MessageBubbleTapAreaは介さない（ジェスチャー競合回避、
              // 2026-08-09追加）。明示的な×ボタンは廃止し、コピー操作
              // （Ctrl+C・選択ツールバーの「コピー」）を検知して自動で
              // モードを終了する。
              child: textCopySelecting
                  ? Actions(
                      actions: <Type, Action<Intent>>{
                        CopySelectionTextIntent:
                            CallbackAction<CopySelectionTextIntent>(
                              onInvoke: (intent) {
                                onCopyPartialSelection?.call();
                                return null;
                              },
                            ),
                      },
                      child: SelectionArea(
                        key: partialCopySelectionKey,
                        onSelectionChanged: onPartialCopySelectionChanged,
                        contextMenuBuilder: (context, state) =>
                            AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: state.contextMenuAnchors,
                              buttonItems: [
                                ContextMenuButtonItem(
                                  type: ContextMenuButtonType.copy,
                                  onPressed: onCopyPartialSelection,
                                ),
                              ],
                            ),
                        child: bubble,
                      ),
                    )
                  : _MessageBubbleTapArea(
                      canSelect: canSelect,
                      strings: strings,
                      onTap: onBubbleTap,
                      onReply: () => onReply?.call(message),
                      onEdit: canEdit ? () => onEdit?.call(message) : null,
                      onUnsend: (isMe && onUnsend != null)
                          ? () => _confirmUnsend(context, strings)
                          : null,
                      onReact: onSetReaction == null ? null : _toggleMyReaction,
                      onCopySelect: () => onCopyMessage?.call(message),
                      onPartialCopySelect: () =>
                          onEnterTextCopy?.call(message.messageId),
                      onSelect: canSelect
                          ? () => onEnterSelection?.call(message.messageId)
                          : null,
                      onScreenshotSelect: canSelect
                          ? () => onEnterScreenshotSelection?.call(
                              message.messageId,
                            )
                          : null,
                      child: bubble,
                    ),
            ),
            if (!alignRight && readBadge != null) ...[
              const SizedBox(width: 6),
              readBadge,
            ],
          ],
        ),
        // リアクションは吹き出しの真下に配置する（2026-08-05変更）。以前は
        // Stack+Positionedで吹き出しの外へ重ねていたが、Positionedの
        // オーバーフロー分は親のColumn/ListViewの高さ計算に含まれず
        // 次のメッセージと重なる上、吹き出し本体のヒットテスト範囲外に
        // なるためタップも一切効かなかった（＋ボタン・リアクション
        // チップともに無反応になっていた）。Column内の実際の子要素として
        // 配置することで、両方を解消する。
        if (hasReactions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _reactionBar(context, strings, alignRight),
          ),
      ],
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
      Widget senderAvatar = _SenderAvatar(
        userId: message.senderId,
        rhingId: message.senderRhingId,
        conversationId: conversationId,
        uiStyle: uiStyle,
      );
      Widget senderName = _SenderName(
        userId: message.senderId,
        rhingId: message.senderRhingId,
        conversationId: conversationId,
        color: senderNameColorResolver?.call(message.senderId),
      );
      if (blurSenderInfo) {
        // プライバシー配慮のスクリーンショット用（[blurSenderInfo]参照）。
        // アイコン・呼び名の見た目そのものをぼかすことで、写真でも初見の
        // 相手でも判読できないようにする。
        final blur = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);
        senderAvatar = ImageFiltered(imageFilter: blur, child: senderAvatar);
        senderName = ImageFiltered(imageFilter: blur, child: senderName);
      }

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
        // contentはAlignで寄せられているため、指定なし（既定の
        // deferToChild）だと吹き出し左右の余白（何も描画されていない
        // 領域）でタップが反応しなかった。opaqueにして行全体で反応する
        // ようにする（2026-08-09修正）。
        behavior: HitTestBehavior.opaque,
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
        onSwipeBack: onSwipeBack,
        alignRight: alignRight,
        child: content,
      );
    }

    // 返信先ジャンプの着地先だと分かるよう、一瞬だけ背景を強調する。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlighted
          ? colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      child: body,
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

  /// contentType='file'|'image'|'video'（添付メッセージ）の表示
  /// （技術仕様書5.2・5.6参照、2026-08-10追加）。画像はサムネイルを直接
  /// 表示しタップで全画面表示、ファイル・動画はアイコン+ファイル名+
  /// サイズを表示しタップでブラウザ等の外部アプリで開く（動画再生用の
  /// パッケージは未導入のため、アプリ内再生ではなく外部起動にとどめる）。
  Widget _attachmentContent(BuildContext context, Color onBubbleColor) {
    final metadata = message.fileMetadata;
    if (metadata == null) {
      return Text(message.content, style: TextStyle(color: onBubbleColor));
    }

    if (message.contentType == 'image') {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImageViewerScreen(url: metadata.url),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            metadata.url,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Icon(Icons.broken_image_outlined, color: onBubbleColor),
          ),
        ),
      );
    }

    final isVideo = message.contentType == 'video';
    return InkWell(
      onTap: () => launchUrl(
        Uri.parse(metadata.url),
        mode: LaunchMode.externalApplication,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo
                ? Icons.videocam_outlined
                : Icons.insert_drive_file_outlined,
            color: onBubbleColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: onBubbleColor),
                ),
                Text(
                  _formatFileSize(metadata.sizeBytes),
                  style: TextStyle(
                    fontSize: 11,
                    color: onBubbleColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)}${units[unitIndex]}';
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
    final showPrompt =
        isDm &&
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
                onPressed: () =>
                    onDeclineAccountDeletionNotice?.call(message.messageId),
                child: Text(strings.chatAccountDeletedNoButton),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _confirmDeleteConversation(context, strings),
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

  /// 自分のこのメッセージへのリアクションを、[emoji]について付け外しする
  /// （既に付けていれば外す、付けていなければ追加する。他の絵文字には
  /// 影響しない。2026-08-05追加、複数の異なる絵文字を同時に付けられる
  /// ようになったことに伴うトグルヘルパー）。長押しメニューからの
  /// リアクション・リアクション行の＋ボタン、両方から使う。
  void _toggleMyReaction(String emoji) {
    final mine = message.reactions[currentUserId] ?? [];
    final next = mine.contains(emoji)
        ? (mine.toSet()..remove(emoji))
        : (mine.toSet()..add(emoji));
    onSetReaction?.call(message.messageId, next.toList());
  }

  /// リアクション（絵文字ごとの重複無しチップ）の一覧＋末尾の＋ボタン。
  /// 吹き出しの真下の`Positioned`内で`Wrap`に並べて表示する
  /// （2026-08-05変更）。[alignRight]が真の時（自分のメッセージが右寄せの
  /// 時）は`Directionality`で列全体を反転し、＋ボタンが左端に来るように
  /// する（絵文字チップ自体の中身はミラーされない）。
  ///
  /// チップをタップしても即座に自分のリアクションを取り消さない
  /// （2026-08-05変更）。代わりに[_showReactionListPopup]でリアクション
  /// 一覧（誰がどの絵文字を付けたか）を表示し、そこで自分の行にのみ
  /// 出るゴミ箱ボタンから取り消す。人数は表示しない（絵文字のみ）。
  Widget _reactionBar(BuildContext context, Strings strings, bool alignRight) {
    final emojis = message.reactions.values.expand((e) => e).toSet();
    final myReactions = message.reactions[currentUserId] ?? [];
    // 劇画スタイルでは、ジグザグ枠にはせず色だけモノクロにする
    // （2026-08-04追加）。以前は選択中（自分のリアクション）だけ白地黒
    // 文字に反転していたが、タップ操作が即トグルではなくリアクション
    // 一覧ポップアップを開く形に変わったため、選択強調の必要性が薄れた。
    // ユーザー指示により常に黒地白文字に統一する（2026-08-05変更）。
    final isGekiga = uiStyle == AppUiStyle.gekiga;

    return Directionality(
      textDirection: alignRight ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        spacing: 4,
        children: [
          for (final emoji in emojis)
            Builder(
              builder: (chipContext) => GestureDetector(
                onTap: () =>
                    _showReactionListPopup(context, chipContext, strings),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isGekiga
                        ? GekigaColors.panel
                        : (myReactions.contains(emoji)
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest),
                    borderRadius: BorderRadius.circular(999),
                    border: isGekiga
                        ? null
                        : (myReactions.contains(emoji)
                              ? Border.all(color: colorScheme.primary)
                              : null),
                  ),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: 12,
                      color: isGekiga ? GekigaColors.onPanel : null,
                    ),
                  ),
                ),
              ),
            ),
          if (emojis.isNotEmpty)
            Builder(
              builder: (addContext) => GestureDetector(
                onTapDown: (details) async {
                  final emoji = await _pickReactionEmoji(
                    addContext,
                    details.globalPosition,
                  );
                  if (emoji != null) _toggleMyReaction(emoji);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isGekiga
                        ? GekigaColors.panel
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    Icons.add_reaction_outlined,
                    size: 14,
                    color: isGekiga ? GekigaColors.onPanel : null,
                  ),
                ),
              ),
            ),
        ],
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

enum _MessageMenuAction {
  reply,
  edit,
  unsend,
  react,
  copy,
  partialCopy,
  select,
  screenshot,
}

/// 長押し/右クリック位置に開く各種メニューの位置決め（[_MessageBubbleTapArea]・
/// [_MessageRow]の＋ボタン双方から使う共通ロジック、2026-08-05切り出し）。
RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
}

/// リアクション絵文字ピッカー（[kReactionEmojis]から1つ選ぶポップアップ）。
/// 長押しメニューの「リアクション」と、リアクション行の＋ボタン双方から
/// 使う共通ロジック（2026-08-05切り出し）。選ばれなければnullを返す。
Future<String?> _pickReactionEmoji(
  BuildContext context,
  Offset globalPosition,
) {
  return showMenu<String>(
    context: context,
    position: _menuPosition(context, globalPosition),
    items: [
      PopupMenuItem<String>(
        // 長押し位置が画面端に近いと、メニューに残る横幅より絵文字6個分の
        // Rowの必要幅が大きくなり、RenderFlexのオーバーフローが発生して
        // いた（2026-08-04発覚・修正）。Wrapにすることで、幅が足りない
        // 位置に開いても画面外へ溢れず折り返すだけになる。
        child: Wrap(
          spacing: 4,
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
}

/// 吹き出し本体だけに絞った当たり判定。長押し/右クリックでリアクション・
/// 返信・編集等のコンテキストメニューを開く（2026-07-29変更: 以前は行全体
/// （余白込み）が対象だったが、余白部分の長押しを自動スクロール
/// （[_MessageInteractions]参照）に割り当てたため、両者が同じ操作を
/// 奪い合わないよう吹き出し本体だけに絞った）。
///
/// 右クリック（[onSecondaryTapDown]）は従来通り`showMenu`でクリック選択の
/// メニューを開くが、長押しは指を離さずメニュー上をスライドし、離した項目が
/// そのまま実行される「ドラッグ選択」方式にしている（2026-08-09変更、
/// ジェスチャーの生存期間をまたいで`OverlayEntry`・ハイライト状態を保持する
/// 必要があるため`StatefulWidget`化した）。
class _MessageBubbleTapArea extends StatefulWidget {
  const _MessageBubbleTapArea({
    required this.child,
    required this.canSelect,
    required this.strings,
    required this.onReply,
    this.onEdit,
    this.onUnsend,
    this.onReact,
    this.onCopySelect,
    this.onPartialCopySelect,
    this.onSelect,
    this.onScreenshotSelect,
    this.onTap,
  });

  final Widget child;
  final bool canSelect;
  final Strings strings;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onUnsend;
  final void Function(String emoji)? onReact;

  /// メッセージ本文全体を即座にクリップボードへコピーする（削除権限の
  /// 有無と無関係のため、[canSelect]と関係なく常に出す、2026-08-09追加、
  /// 選択操作を挟まない即時実行）。
  final VoidCallback? onCopySelect;

  /// 部分コピー用の文言選択モードに入る（[onCopySelect]の即時コピーとは
  /// 別のアクション、2026-08-09追加）。全文選択済みの状態から始まり、
  /// カーソルでコピーしたい範囲だけに絞り込める。
  final VoidCallback? onPartialCopySelect;

  /// 「メッセージを削除」用の複数選択モードに入る。
  final VoidCallback? onSelect;

  /// スクリーンショット用の範囲選択モードに入る（[onSelect]とは別モード、
  /// 2026-08-09追加）。
  final VoidCallback? onScreenshotSelect;

  /// 返信先ジャンプ用のタップ。nullなら通常通りタップでは何も起きない。
  final VoidCallback? onTap;

  @override
  State<_MessageBubbleTapArea> createState() => _MessageBubbleTapAreaState();
}

class _MessageBubbleTapAreaState extends State<_MessageBubbleTapArea> {
  final _highlightIndex = ValueNotifier<int>(-1);
  OverlayEntry? _overlayEntry;
  DragMenuGeometry? _dragMenuGeometry;
  List<({_MessageMenuAction action, String label})> _dragMenuItems = const [];

  @override
  void dispose() {
    _removeOverlay();
    _highlightIndex.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _dragMenuGeometry = null;
  }

  /// メニュー項目の並び（`onReact`/`onEdit`/`onUnsend`のnull有無・
  /// [_MessageBubbleTapArea.canSelect]によるガードを含む）。右クリックの
  /// `showMenu`・長押しのドラッグメニュー両方で共有する（2026-08-09切り出し）。
  List<({_MessageMenuAction action, String label})> _buildMenuItems() {
    final strings = widget.strings;
    return [
      (action: _MessageMenuAction.reply, label: strings.chatReplyAction),
      if (widget.onReact != null)
        (action: _MessageMenuAction.react, label: strings.chatReactAction),
      if (widget.onEdit != null)
        (action: _MessageMenuAction.edit, label: strings.chatEditAction),
      if (widget.onUnsend != null)
        (action: _MessageMenuAction.unsend, label: strings.chatUnsendAction),
      (action: _MessageMenuAction.copy, label: strings.chatCopyAction),
      (
        action: _MessageMenuAction.partialCopy,
        label: strings.chatPartialCopyAction,
      ),
      if (widget.canSelect) ...[
        (action: _MessageMenuAction.select, label: strings.chatSelectAction),
        (
          action: _MessageMenuAction.screenshot,
          label: strings.chatScreenshotAction,
        ),
      ],
    ];
  }

  /// 右クリック・ドラッグメニュー双方から呼ばれるアクションの実行本体
  /// （2026-08-09切り出し）。
  Future<void> _handleAction(
    BuildContext context,
    _MessageMenuAction? action,
    Offset globalPosition,
  ) async {
    if (!context.mounted) return;
    switch (action) {
      case _MessageMenuAction.reply:
        widget.onReply();
      case _MessageMenuAction.edit:
        widget.onEdit?.call();
      case _MessageMenuAction.unsend:
        widget.onUnsend?.call();
      case _MessageMenuAction.react:
        final emoji = await _pickReactionEmoji(context, globalPosition);
        if (emoji != null) widget.onReact?.call(emoji);
      case _MessageMenuAction.copy:
        widget.onCopySelect?.call();
      case _MessageMenuAction.partialCopy:
        widget.onPartialCopySelect?.call();
      case _MessageMenuAction.select:
        widget.onSelect?.call();
      case _MessageMenuAction.screenshot:
        widget.onScreenshotSelect?.call();
      case null:
        break;
    }
  }

  /// 右クリック用、従来通りのクリック選択メニュー（変更なし）。
  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final items = _buildMenuItems();
    final action = await showMenu<_MessageMenuAction>(
      context: context,
      position: _menuPosition(context, globalPosition),
      items: [
        for (final item in items)
          PopupMenuItem(value: item.action, child: Text(item.label)),
      ],
    );
    if (!context.mounted) return;
    await _handleAction(context, action, globalPosition);
  }

  void _onLongPressStart(BuildContext context, LongPressStartDetails details) {
    final items = _buildMenuItems();
    final colorScheme = Theme.of(context).colorScheme;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screenSize = overlayBox.size;
    final textStyle = Theme.of(context).textTheme.bodyLarge!;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    const hPad = 16.0;
    var maxLabelWidth = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: textStyle),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      if (painter.width > maxLabelWidth) maxLabelWidth = painter.width;
    }
    final menuWidth = (maxLabelWidth + hPad * 2).clamp(140.0, 280.0);
    final menuHeight = kDragMenuItemHeight * items.length;

    const screenPad = 8.0;
    final left = details.globalPosition.dx.clamp(
      screenPad,
      screenSize.width - menuWidth - screenPad,
    );
    final top = details.globalPosition.dy.clamp(
      screenPad,
      screenSize.height - menuHeight - screenPad,
    );

    final geometry = DragMenuGeometry(
      left: left,
      top: top,
      width: menuWidth,
      itemCount: items.length,
    );
    _dragMenuItems = items;
    _dragMenuGeometry = geometry;
    _highlightIndex.value = geometry.hitTest(details.globalPosition);

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // メニュー表示中、下のメッセージ一覧が誤って反応しないようにする
          // バリア（showMenuのルートが持つ効果に近づける）。
          const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
          Positioned(
            left: geometry.left,
            top: geometry.top,
            width: geometry.width,
            height: geometry.height,
            child: Material(
              color: colorScheme.surfaceContainer,
              elevation: 3,
              shadowColor: colorScheme.shadow,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _highlightIndex,
                builder: (_, highlighted, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Container(
                        height: kDragMenuItemHeight,
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsets.symmetric(horizontal: hPad),
                        color: i == highlighted
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            color: i == highlighted
                                ? colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final geometry = _dragMenuGeometry;
    if (geometry == null) return;
    _highlightIndex.value = geometry.hitTest(details.globalPosition);
  }

  void _onLongPressEnd(BuildContext context, LongPressEndDetails details) {
    final geometry = _dragMenuGeometry;
    final items = _dragMenuItems;
    _removeOverlay();
    if (geometry == null) return;
    final index = geometry.hitTest(details.globalPosition);
    if (index < 0) return;
    _handleAction(context, items[index].action, details.globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: (details) => _onLongPressStart(context, details),
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: (details) => _onLongPressEnd(context, details),
      onLongPressCancel: _removeOverlay,
      onSecondaryTapDown: (details) =>
          _openMenu(context, details.globalPosition),
      child: widget.child,
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
    this.onSwipeBack,
    this.alignRight = false,
  });

  final Widget child;
  final bool canEdit;
  final VoidCallback onReply;
  final VoidCallback? onEdit;

  final ValueChanged<Offset>? onAutoScrollStart;
  final ValueChanged<Offset>? onAutoScrollUpdate;
  final VoidCallback? onAutoScrollEnd;

  /// 縦表示で、吹き出しの上を右スワイプした時に会話一覧へ戻る処理
  /// （[ChatScreen.onSwipeBack]参照、2026-08-06追加）。
  final VoidCallback? onSwipeBack;

  /// 右寄せ表示（自分のメッセージ・sideBySideレイアウト）かどうか。真の時は
  /// [onSwipeBack]を無効にする（ユーザー指定の除外仕様）。
  final bool alignRight;

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
    } else if (!widget.alignRight &&
        details.primaryVelocity != null &&
        details.primaryVelocity! >= kSwipeGestureVelocityThreshold) {
      // 吹き出しの上は返信/編集用の左スワイプをこのGestureDetector自身が
      // 無条件に受理してしまい、外側のSwipeBackDetector（吹き出しの無い
      // 余白では機能する）にジェスチャーアリーナ上伝播しないため、右スワイプ
      // で会話一覧へ戻る処理をここに直接組み込む（2026-08-06追加）。
      widget.onSwipeBack?.call();
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
    final id = rhingId ?? '?';
    final color = _palette[id.hashCode.abs() % _palette.length];
    if (uiStyle == AppUiStyle.gekiga) {
      return GekigaPhotoFrame(
        size: 48,
        image: iconUrl != null ? NetworkImage(iconUrl) : null,
        fallback: iconUrl != null
            ? null
            : ColoredBox(
                color: color,
                child: Center(
                  child: Text(
                    id[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
      );
    }
    if (iconUrl != null) {
      return CircleAvatar(radius: 16, backgroundImage: NetworkImage(iconUrl));
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Text(
        id[0].toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

/// 添付画像メッセージのサムネイルをタップした時の全画面表示
/// （[_MessageRow._attachmentContent]参照、2026-08-10追加）。
class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(child: InteractiveViewer(child: Image.network(url))),
    );
  }
}

/// 劇画スタイルの吹き出し本体。歪な平行四辺形＋他のモノクロボックス系と
/// 同じ黒外枠・白中枠・地色の3層塗り（2026-07-29追加、2026-08-09に
/// コミック風バナー形状＋単純な塗り+枠線から現在の形へ変更）。自分は
/// 白地に黒文字（外枠・中枠も反転）、相手は黒地に白文字で白黒反転する。
class _GekigaBubble extends StatelessWidget {
  const _GekigaBubble({
    required this.child,
    required this.seed,
    required this.isMe,
    required this.alignRight,
  });

  final Widget child;
  final int seed;
  final bool isMe;

  /// 右寄せ表示（自分・sideBySideレイアウト）かどうか。真なら吹き出しの
  /// 形状（平行四辺形の傾き）を左右反転する（2026-08-06追加）。
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GekigaBubblePainter(
        seed: seed,
        isMe: isMe,
        alignRight: alignRight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: child,
      ),
    );
  }
}

class _GekigaBubblePainter extends CustomPainter {
  const _GekigaBubblePainter({
    required this.seed,
    required this.isMe,
    required this.alignRight,
  });

  final int seed;
  final bool isMe;
  final bool alignRight;

  @override
  void paint(Canvas canvas, Size size) {
    final vertices = distortedParallelogramVertices(
      size.width,
      size.height,
      seed,
    );
    MonochromeBoxPainter(
      vertices: alignRight ? mirrorHorizontal(vertices, size.width) : vertices,
      thicknessBase: size.shortestSide,
      fillColor: isMe ? Colors.white : Colors.black,
      seed: seed,
      invert: isMe,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GekigaBubblePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.isMe != isMe ||
      oldDelegate.alignRight != alignRight;
}

/// 劇画スタイルの入力欄の外枠。自分のメッセージ吹き出し（[_GekigaBubble]、
/// `isMe: true`）と同じ「歪な平行四辺形＋モノクロボックス」の意匠を使う
/// （2026-08-10追加）。メッセージと違い個別のidを持たないため、`seed`は
/// 固定値にし、入力中に形状がガタつかないようにする。
class _GekigaComposerField extends StatelessWidget {
  const _GekigaComposerField({required this.child});

  final Widget child;

  /// 固定シード。メッセージ吹き出しのようなid由来の値を持たないため、
  /// 常に同じ歪みで安定させる。
  static const _seed = 0xDA1DA1;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _GekigaComposerFieldPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: child,
      ),
    );
  }
}

class _GekigaComposerFieldPainter extends CustomPainter {
  const _GekigaComposerFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const seed = _GekigaComposerField._seed;
    final vertices = mirrorHorizontal(
      distortedParallelogramVertices(size.width, size.height, seed),
      size.width,
    );
    MonochromeBoxPainter(
      vertices: vertices,
      thicknessBase: size.shortestSide,
      fillColor: Colors.white,
      seed: seed,
      invert: true,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GekigaComposerFieldPainter oldDelegate) =>
      false;
}
