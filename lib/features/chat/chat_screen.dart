import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderRepaintBoundary, SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../call/camera_availability.dart';
import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/chat_layout_style.dart';
import '../../models/conversation_prefs.dart';
import '../../models/message.dart';
import '../../models/message_time_format.dart';
import '../../models/send_key_mode.dart';
import '../../models/sticker.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/draft_sync_enabled_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../theme/app_theme_extras.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';
import '../../widgets/gekiga/monochrome_box.dart';
import '../../widgets/media_preview_frame.dart';
import 'attachment_popup_button.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/drag_menu_geometry.dart';
import '../../utils/fullscreen/fullscreen.dart';
import '../../utils/link_detection.dart';
import 'sticker_picker_popup.dart';
import 'sticker_picker_sheet.dart';
import 'talks_tab.dart' show kTalksSplitBreakpoint;
import '../../utils/message_time.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_photo_frame.dart';
import '../../widgets/link_preview_card.dart';
import '../../widgets/linkified_text.dart';
import '../../widgets/swipe_gestures.dart'
    show SwipeDownToDismiss, kSwipeGestureVelocityThreshold;

/// 劇画UIの吹き出し・入力欄の枠取りの太さ（[MonochromeBoxPainter]の
/// thicknessBase）。以前は`size.shortestSide`（箱の短辺）に比例させて
/// いたが、箱の形が極端になる（複数行の吹き出しが縦長になる／入力欄が
/// 複数行で縦に伸びる）と枠が際限なく太くなり、固定の内側余白を超えて
/// 文字と重なる不具合があった（2026-08-12発覚）。箱のサイズに関わらず
/// 固定値にすることで解消する。
const double _kGekigaBoxBorderThickness = 40.0;

/// 一対・広場（お部屋）どちらの会話でも使える汎用チャット画面。
/// メッセージの取得・送信方法は呼び出し元がstream/callbackとして渡す。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.title,
    required this.currentUserId,
    required this.isDm,
    this.conversationId,
    required this.messagesStream,
    this.onSend,
    this.onSendAttachment,
    this.onSendSticker,
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
    this.onLoadOlderMessages,
    this.isLoadingOlderMessages = false,
    this.hasMoreHistory = true,
    this.roomTabBar,
    this.disabled = false,
    this.onSwipeBack,
    this.roomId,
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

  /// nullなら入力欄（コンポーザー）自体を表示しない（お知らせ等の
  /// 読み取り専用画面向け、2026-08-12追加）。
  final Future<void> Function(String content, {bool silent, Message? replyTo})?
  onSend;

  /// ファイル・画像・動画を添付したメッセージを送信する（技術仕様書5.6参照、
  /// 2026-08-10追加）。nullなら＋ボタン自体を表示しない（承認待ちの一対・
  /// 広場を開いた際の`disabled`なプレースホルダー画面など）。
  final Future<void> Function(PickedAttachment attachment)? onSendAttachment;

  /// ペタピタ（スタンプ）を送信する（技術仕様書7.4参照、2026-08-11追加）。
  /// nullなら＋ボタンのメニューに「ペタピタ」項目自体を出さない。
  final Future<void> Function(Sticker sticker)? onSendSticker;

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

  /// メッセージ一覧を一番上（一番古いメッセージ側）までスクロールした時に、
  /// さらに古い暦日1日分を読み込む（2026-08-20追加、1日単位ページネーション）。
  /// nullならこの機能自体を使わない（呼び出し元が[messagesStream]を1日単位
  /// ページネーションに対応させていない場合）。
  final Future<void> Function()? onLoadOlderMessages;

  /// [onLoadOlderMessages]が現在実行中かどうか。trueの間は一覧の最上部に
  /// ローディング表示を出し、スクロールでの再発火を防ぐ。
  final bool isLoadingOlderMessages;

  /// これ以上遡れる履歴が無いかどうか。falseなら一覧の最上部に終端表示を
  /// 出し、[onLoadOlderMessages]をこれ以上呼ばない。
  final bool hasMoreHistory;

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

  /// 寄合単位の下書き同期（`draftSyncEnabledProvider`、2026-08-13追加）の
  /// キーに使う現在表示中の寄合id。[conversationId]が一対のdmId/広場の
  /// groupIdを表すのに対し、こちらは寄合（`DmRoom.roomId`/`Room.roomId`）
  /// 単位。nullなら下書き同期機能自体を無効化する（お知らせ画面・承認待ち
  /// プレースホルダー等、下書きの概念が無い呼び出し元向け）。
  final String? roomId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();

  /// 入力欄の下書き複数端末同期用（2026-08-13追加）。デバウンス書き込みの
  /// タイマーと、編集モード中など「今の入力内容を下書きとして書き込んで
  /// はいけない」場面で立てる抑制フラグ。
  Timer? _draftSaveTimer;
  bool _suppressDraftSync = false;

  /// 他端末の下書き変化を継続的に購読するための手動購読（2026-08-20追加）。
  /// 以前は`initState`で一度だけ読み込むだけで、開いたまま他端末の下書きが
  /// 変わっても・後から開き直しても反映されない不具合があったため、
  /// `ref.listenManual`による永続購読に置き換えた（[_applyRemoteDraft]参照）。
  ProviderSubscription<AsyncValue<Map<String, ConversationPrefs>>>? _draftSub;

  // widget.roomIdがnullな呼び出し元（お知らせ画面等、既存テストの多くも
  // 含む）でdraftSyncEnabledProviderの評価自体をスキップするため、
  // 軽量なnullチェックを先に置く（先にref.read(draftSyncEnabledProvider)を
  // 評価すると、ProviderScopeがinitialDraftSyncEnabledProviderをoverride
  // していない場面で無関係にUnimplementedErrorが飛んでしまう）。
  bool get _draftSyncActive =>
      widget.conversationId != null &&
      widget.roomId != null &&
      widget.onSend != null &&
      ref.read(draftSyncEnabledProvider);

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onComposerTextChanged);
    if (_draftSyncActive) {
      _draftSub = ref.listenManual(
        conversationPrefsProvider(widget.currentUserId),
        (previous, next) => _applyRemoteDraft(next.value),
        fireImmediately: true,
      );
    }
    _itemPositionsListener.itemPositions.addListener(_maybeLoadOlderMessages);
  }

  /// メッセージ一覧（`reverse:true`の`ScrollablePositionedList`）の一番古い
  /// メッセージ側の端に近づいたら、[ChatScreen.onLoadOlderMessages]でさらに
  /// 古い暦日を読み込む（2026-08-20追加、1日単位ページネーション）。
  /// `reverse:true`のため、indexが大きいほど古いメッセージ側（画面上端）
  /// にいる。
  void _maybeLoadOlderMessages() {
    final onLoadOlderMessages = widget.onLoadOlderMessages;
    if (onLoadOlderMessages == null) return;
    if (widget.isLoadingOlderMessages || !widget.hasMoreHistory) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _entryCount == 0) return;
    final maxIndex = positions.map((p) => p.index).reduce(math.max);
    if (_entryCount - 1 - maxIndex <= 5) {
      onLoadOlderMessages();
    }
  }

  /// 他端末の下書き（`draftByRoom[roomId]`）が変化した時に呼ばれる。画面を
  /// 開いた瞬間の復元（`fireImmediately`）と、開いたまま他端末の下書きが
  /// 変わった場合の反映を同じ経路で行う（2026-08-20変更、以前は`initState`
  /// で一度だけ読み込むだけで、開いたまま他端末の下書きが変わっても・後から
  /// 開き直しても反映されない不具合があった）。フォーカス中（＝今まさに
  /// このタブで入力中）の間だけは上書きしない。以前は「入力欄が既に非空」
  /// も上書き抑制の条件にしていたが、それだと最初の同期（空→内容あり）が
  /// 一度成功した後は以後ずっとブロックされ続け、他端末で下書きを消した
  /// （空文字列に戻した）操作が一切反映されない不具合になっていたため外した
  /// （2026-08-20修正）。
  void _applyRemoteDraft(Map<String, ConversationPrefs>? prefsMap) {
    if (!mounted || prefsMap == null || _composerFocusNode.hasFocus) return;
    final draft =
        prefsMap[widget.conversationId!]?.draftByRoom[widget.roomId!] ?? '';
    if (draft == _textController.text) return;
    _suppressDraftSync = true;
    _textController.text = draft;
    _suppressDraftSync = false;
  }

  void _onComposerTextChanged() {
    if (_suppressDraftSync || _editingMessage != null) return;
    if (!_draftSyncActive) return;
    _draftSaveTimer?.cancel();
    final text = _textController.text;
    _draftSaveTimer = Timer(const Duration(milliseconds: 600), () {
      ref
          .read(conversationPrefsRepositoryProvider)
          .setDraft(
            userId: widget.currentUserId,
            conversationId: widget.conversationId!,
            roomId: widget.roomId!,
            draft: text,
          );
    });
  }

  /// 送信直後など、下書きを即座に消したい時に呼ぶ（デバウンス待ちを挟まない）。
  void _clearDraftNow() {
    _draftSaveTimer?.cancel();
    if (!_draftSyncActive) return;
    ref
        .read(conversationPrefsRepositoryProvider)
        .setDraft(
          userId: widget.currentUserId,
          conversationId: widget.conversationId!,
          roomId: widget.roomId!,
          draft: '',
        );
  }

  /// テキスト入力欄のフォーカス制御用（2026-08-12追加）。返信モード開始時に
  /// 自動的にフォーカスを当てる、送信ボタンにフォーカスを奪われないよう
  /// 送信直後に取り戻す、の2用途で使う（[_startReply]/[_send]参照）。
  final _composerFocusNode = FocusNode();

  /// メッセージ一覧（`ScrollablePositionedList`）のスクロール制御・位置監視用
  /// （2026-08-21、`ListView`+`GlobalKey`+`Scrollable.ensureVisible`方式から
  /// 移行。返信先ジャンプ機能は`_itemScrollController.jumpTo(index:)`で
  /// 未ビルドの行にも確定的にジャンプできる）。
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

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

  /// メッセージ入力欄右端の専用ペタピタ送信アイコン（2026-08-11追加）の
  /// アンカー位置計算用。デスクトップ幅ではこのキーを基準に
  /// [showStickerPickerPopup]でアイコン付近にポップアップを浮かせる。
  final _stickerButtonKey = GlobalKey();

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

  /// 返信先ジャンプ機能用に、現在表示中の各メッセージ行の
  /// `ScrollablePositionedList`上のインデックス（2026-08-21、`GlobalKey`＋
  /// `Scrollable.ensureVisible`方式から移行）。build()内でsetStateを介さず
  /// 直接更新する（[_cachedMessages]と同じパターン、このフィールド自体は
  /// 再描画のトリガーにする必要が無いため）。
  Map<String, int> _messageIndexById = {};

  /// [_messageIndexById]構築時点でのメッセージ一覧の総行数
  /// （日付区切り等を含む、[_maybeLoadOlderMessages]の閾値判定用）。
  int _entryCount = 0;

  /// [widget.messagesStream]に含まれない返信先へジャンプする際、
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

  /// 返信元メッセージへジャンプする（2026-08-21、`ScrollablePositionedList`
  /// への移行に伴い書き換え）。`ItemScrollController.jumpTo(index:)`は
  /// 対象行が事前にビルドされていなくても確定的にジャンプできるため、旧実装
  /// にあったGlobalKeyのビルド待ちリトライ・`Scrollable.ensureVisible`の
  /// 再試行は不要になった。
  Future<void> _jumpToMessage(String messageId) async {
    var index = _messageIndexById[messageId];
    if (index == null) {
      final fetched = await widget.onFetchMessagesAround?.call(messageId);
      if (!mounted) return;
      if (fetched == null || fetched.isEmpty) {
        // フェッチしても存在しない＝対象メッセージが本当に無い
        // （全員から削除され物理削除済み等）と確定できるケース。
        _showJumpNotFoundBanner();
        return;
      }
      setState(() {
        for (final message in fetched) {
          _extraMessages[message.messageId] = message;
        }
      });
      // フェッチ結果がbuild()に反映され_messageIndexByIdへ載るまで1フレーム待つ。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      index = _messageIndexById[messageId];
    }
    if (index == null || !_itemScrollController.isAttached) {
      _showJumpNotFoundBanner();
      return;
    }

    _itemScrollController.jumpTo(index: index, alignment: 0.5);

    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  /// [_jumpToMessage]で返信元メッセージが見つからなかった場合の通知。参加者
  /// 全員がその後削除し物理削除済みのメッセージへの返信等で恒久的に起こり
  /// うるため、無反応のままにせず理由を伝える（2026-08-14追加）。
  void _showJumpNotFoundBanner() {
    showAutoDismissBanner(context, message: '元のメッセージが見つかりません');
  }

  void _startReply(Message message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocusNode.requestFocus();
  }

  void _startEdit(Message message) {
    // 編集対象メッセージの本文で、この寄合の下書きを上書きしないよう
    // 書き込みリスナーを止めておく（2026-08-13追加）。
    _suppressDraftSync = true;
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _textController.text = message.content;
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelComposerContext() {
    final wasEditing = _editingMessage != null;
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
      if (wasEditing) _textController.clear();
    });
    if (wasEditing) _suppressDraftSync = false;
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
  /// 即時実行アクション）。完了通知は表示しない（2026-08-12、成功通知の
  /// 全面廃止方針）。
  Future<void> _copyMessageText(Message message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
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
    final vocabulary = ref.read(vocabularyProvider);
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
      _bannerTimer = showAutoDismissBanner(
        context,
        message: strings.chatScreenshotErrorMessage,
        previousTimer: _bannerTimer,
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
          vocabulary: vocabulary,
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
        _bannerTimer = showAutoDismissBanner(
          context,
          message: strings.chatScreenshotErrorMessage,
          previousTimer: _bannerTimer,
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
        _bannerTimer = showAutoDismissBanner(
          context,
          message: strings.chatScreenshotErrorMessage,
          previousTimer: _bannerTimer,
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
    if (widget.onSend == null || widget.disabled) return;
    final content = _textController.text.trim();
    if (content.isEmpty) return;

    if (_editingMessage != null) {
      final messageId = _editingMessage!.messageId;
      _textController.clear();
      _composerFocusNode.requestFocus();
      setState(() => _editingMessage = null);
      _suppressDraftSync = false;
      await widget.onEditMessage?.call(messageId, content);
      return;
    }

    final replyTo = _replyingTo;
    _textController.clear();
    // 送信済みなのでこの寄合の下書きは残さない（デバウンス待ちを挟まず
    // 即座に消す、2026-08-13追加）。
    _clearDraftNow();
    // 送信ボタン（`InkWell`）のタップでフォーカスを奪われても、モバイルで
    // ソフトウェアキーボードが閉じないよう、送信直後にテキスト欄へ
    // フォーカスを戻す（2026-08-12、送信ボタン側のcanRequestFocus:false
    // と合わせて対処）。
    _composerFocusNode.requestFocus();
    setState(() => _replyingTo = null);
    await widget.onSend!(content, silent: silent, replyTo: replyTo);
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
      final canResend =
          e is! AttachmentTooLargeException &&
          e is! AttachmentExtensionBlockedException;
      _bannerTimer = showAutoDismissBanner(
        context,
        message: message,
        previousTimer: _bannerTimer,
        actions: [
          if (canResend)
            TextButton(
              onPressed: () {
                dismissAutoDismissBanner();
                _handleAttachmentPicked(attachment);
              },
              child: Text(strings.chatResendAction),
            )
          else
            TextButton(
              onPressed: dismissAutoDismissBanner,
              child: Text(strings.cancel),
            ),
        ],
      );
    }
  }

  /// ペタピタ（スタンプ）選択時の送信処理。バイトデータのアップロードを
  /// 伴わないため添付ファイルより単純だが、失敗時のバナー表示・再送導線は
  /// [_handleAttachmentPicked]と同じパターンを踏襲する（2026-08-11追加）。
  Future<void> _handleStickerPicked(Sticker sticker) async {
    final onSendSticker = widget.onSendSticker;
    if (onSendSticker == null) return;
    try {
      await onSendSticker(sticker);
    } catch (_) {
      if (!mounted) return;
      final strings = ref.read(appStringsProvider);
      _bannerTimer = showAutoDismissBanner(
        context,
        message: strings.chatAttachmentSendFailedMessage,
        previousTimer: _bannerTimer,
        actions: [
          TextButton(
            onPressed: () {
              dismissAutoDismissBanner();
              _handleStickerPicked(sticker);
            },
            child: Text(strings.chatResendAction),
          ),
        ],
      );
    }
  }

  /// メッセージ入力欄右端の専用ペタピタ送信アイコンのタップ処理
  /// （2026-08-11追加）。既存の「＋」ボタン内のペタピタ項目とは別の近道で、
  /// 画面幅で表示形式を切り替える：コンピューターUI（`kTalksSplitBreakpoint`
  /// 以上）はアイコン付近にアンカー表示するポップアップ、モバイルUIは
  /// ボトムシート（[StickerPickerSheet]、＋ボタン側と共通）。
  Future<void> _openStickerPicker() async {
    final isWide = MediaQuery.sizeOf(context).width >= kTalksSplitBreakpoint;
    final sticker = isWide
        ? await showStickerPickerPopup(
            context,
            anchorRect: _anchorRectFromContext(
              _stickerButtonKey.currentContext!,
            ),
          )
        : await showModalBottomSheet<Sticker>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const StickerPickerSheet(),
          );
    if (sticker == null || !mounted) return;
    await _handleStickerPicked(sticker);
  }

  /// テキスト欄の`suffixIcon`に埋め込むペタピタ送信アイコン本体。
  /// [_openStickerPicker]の項のコメント参照。劇画スタイルの入力欄
  /// （`_GekigaComposerField`）は白い吹き出しに黒文字・黒カーソルという
  /// 配色（`_GekigaComposerFieldPainter`の`fillColor: Colors.white`参照）
  /// のため、アイコンも同じ黒で明示しないとダークテーマのIconThemeから
  /// 白が継承され、白背景に白アイコンで見えなくなる（2026-08-11修正）。
  /// 通常スタイルは他画面のsuffixIcon（例:
  /// `settings_tab.dart`のアクセントカラー入力欄）と同じくTheme既定に
  /// 委ねて問題ないため、明示しない。
  Widget? _stickerComposerButton({required bool isGekiga}) {
    if (widget.onSendSticker == null || widget.disabled) return null;
    return IconButton(
      key: _stickerButtonKey,
      icon: Icon(
        Icons.emoji_emotions_outlined,
        color: isGekiga ? Colors.black : null,
      ),
      onPressed: _openStickerPicker,
    );
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

  /// このチャット画面で表示する通知バナー（添付・ペタピタ送信失敗、
  /// スクリーンショットのキャプチャ・共有失敗等）を3秒後に自動的に
  /// 閉じるためのタイマー（2026-08-10導入、2026-08-12に用途を拡張し
  /// 共通の[showAutoDismissBanner]ヘルパーを使う形にリファクタ）。
  Timer? _bannerTimer;

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _draftSub?.close();
    _textController.removeListener(_onComposerTextChanged);
    _textController.dispose();
    _composerFocusNode.dispose();
    _itemPositionsListener.itemPositions.removeListener(
      _maybeLoadOlderMessages,
    );
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final locale = ref.watch(appLocaleProvider);
    final layoutStyle = ref.watch(chatLayoutStyleProvider);
    final strings = ref.watch(appStringsProvider);
    // ペタピタ送信を使わない呼び出し元（テストの素朴なChatScreen構築を含む）に
    // 新規プロバイダの購読を強制しないよう、実際に必要な場合のみwatchする。
    final vocabulary = widget.onSendSticker == null
        ? null
        : ref.watch(vocabularyProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    // 端末にカメラが1台も無いと判定できた場合、ビデオ通話の発信自体を
    // 出さない（2026-08-19追加、通話UIの簡略化に伴う。判定は起動後1回のみ
    // 実行してキャッシュされる。cameraAvailabilityProviderのdocコメント
    // 参照）。
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
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

    // `primary`はtoolbar行を`RoomTabBar`と共にColumnへ組み込む場合
    // （下記`roomTabBar`の分岐）に、外側の`SafeArea`と二重にtop paddingが
    // 付かないよう呼び出し側で`false`を渡す（2026-08-11追加）。
    AppBar buildToolbar({bool primary = true}) {
      return AppBar(
        primary: primary,
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
        // 表示は別物なので維持する。フラットスタイルは現状通り表示）。
        title: _selecting
            ? Text(strings.chatSelectionModeTitle(_selectedMessageIds.length))
            : _screenshotSelecting
            ? Text(
                strings.chatScreenshotSelectionModeTitle(
                  _screenshotEffectiveIds(_cachedMessages).length,
                ),
              )
            : (isGekiga || widget.title.isEmpty ? null : Text(widget.title)),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selectedMessageIds.isEmpty
                      ? null
                      : _confirmDeleteSelected,
                ),
              ]
            : _screenshotSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
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
                  if (cameraAvailability != CameraAvailability.unavailable)
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
      );
    }

    // 狭い画面（`widget.roomTabBar`が非null）では、寄合タブ帯を通話・
    // ハンバーガーメニューのアイコン行より上に表示する（2026-08-11変更、
    // 以前はAppBar.bottomでアイコン行の下に表示していた）。広い画面
    // （サイドバー`RoomListPane`使用、`roomTabBar`は渡されない）は
    // 従来通り単一のAppBarのまま。
    final roomTabBar = widget.roomTabBar;
    final appBar = roomTabBar == null
        ? buildToolbar()
        : PreferredSize(
            preferredSize: Size.fromHeight(
              kToolbarHeight + roomTabBar.preferredSize.height,
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  roomTabBar,
                  SizedBox(
                    height: kToolbarHeight,
                    child: buildToolbar(primary: false),
                  ),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          if (widget.banner != null) widget.banner!,
          Expanded(
            child: Stack(
              key: _autoScrollAreaKey,
              children: [
                StreamBuilder<List<Message>>(
                  stream: widget.messagesStream,
                  builder: (context, snapshot) {
                    // snapshot.hasDataも確認する（2026-08-20追加）。
                    // streamが（何らかの理由で）再購読された場合でも、
                    // 既にデータを表示済みならメッセージ一覧のListView
                    // （＝スクロール位置）を再構築でリセットしないための
                    // 防御的な措置。根本的な対策は呼び出し元
                    // （`DmChatPane`/`GroupChatPane`）がmessagesStream
                    // 自体のidentityを固定していること。
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: _composerAreaHeight),
                        child: const Center(child: CircularProgressIndicator()),
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

                    // 画像/動画の拡大表示（`_MediaViewerScreen`）での
                    // 前後スワイプ・矢印キーナビゲーション用（2026-08-14
                    // 追加）。`combined`は新しい順なので反転して古い順にする
                    // （右スワイプ＝前＝古い方向、という仕様に合わせるため）。
                    final mediaMessages = combined
                        .where(
                          (m) =>
                              m.contentType == 'image' ||
                              m.contentType == 'video',
                        )
                        .toList()
                        .reversed
                        .toList();

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
                    // 1日単位ページネーション対応の呼び出し元
                    // （onLoadOlderMessagesが非null）の場合のみ、一覧の
                    // 一番古いメッセージ側の端（entries[0]、reverse:trueの
                    // ListViewでは画面上端）にローディング／終端表示を
                    // 追加する（2026-08-20追加）。
                    if (widget.onLoadOlderMessages != null) {
                      if (widget.isLoadingOlderMessages) {
                        entries.add(
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        );
                      } else if (!widget.hasMoreHistory) {
                        entries.add(
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                strings.chatNoMoreHistory,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    }
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
                          key: ValueKey(message.messageId),
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
                              ? _selectedMessageIds.contains(message.messageId)
                              : screenshotEffectiveIds.contains(
                                  message.messageId,
                                ),
                          canSelect: widget.onHideMessages != null,
                          onEnterSelection: _enterSelectionMode,
                          onEnterScreenshotSelection: _enterScreenshotSelection,
                          textCopySelecting:
                              _textCopyMessageId == message.messageId,
                          onEnterTextCopy: _enterTextCopyMode,
                          partialCopySelectionKey: _partialCopyKey,
                          onPartialCopySelectionChanged: (content) =>
                              _partialCopySelectedContent = content,
                          onCopyPartialSelection: _copyPartialSelectionAndExit,
                          onCopyMessage: _copyMessageText,
                          onToggleSelected: _selecting
                              ? _toggleSelected
                              : (_screenshotSelecting
                                    ? _toggleScreenshotSelected
                                    : null),
                          messagesById: messagesById,
                          mediaMessages: mediaMessages,
                          onReply: widget.onSend != null ? _startReply : null,
                          onEdit: widget.onEditMessage != null
                              ? _startEdit
                              : null,
                          onUnsend: widget.onUnsendMessage,
                          onSetReaction: widget.onSetReaction,
                          onJumpToReply: _jumpToMessage,
                          onSendSticker: widget.onSendSticker != null
                              ? _handleStickerPicked
                              : null,
                          stickerButtonKey: _stickerButtonKey,
                          highlighted:
                              _highlightedMessageId == message.messageId,
                          timeFormat: timeFormat,
                          onDeclineAccountDeletionNotice:
                              widget.onDeclineAccountDeletionNotice,
                          onDeleteAfterAccountDeletion:
                              widget.onDeleteAfterAccountDeletion,
                          onSwipeBack: widget.onSwipeBack,
                          vocabulary: vocabulary,
                        ),
                      );
                    }
                    final reversedEntries = entries.reversed.toList();

                    // 返信先ジャンプ機能（_jumpToMessage）用に、messageIdから
                    // ScrollablePositionedList上のインデックスを引けるように
                    // しておく（2026-08-21、ItemScrollController.jumpTo(index:)
                    // は対象が未ビルドでも確定的にジャンプできるため、旧実装の
                    // ような「ロード済みは最新50件程度」という前提は不要）。
                    _entryCount = reversedEntries.length;
                    _messageIndexById = {
                      for (var i = 0; i < reversedEntries.length; i++)
                        if (reversedEntries[i] is _MessageRow)
                          (reversedEntries[i] as _MessageRow).message.messageId:
                              i,
                    };

                    // メッセージ一覧は入力欄の裏まで全画面分の高さで敷き、
                    // 入力欄自体はStack最前面のオーバーレイとして重ねる
                    // （下記Positioned参照）。下部余白（bottomInset）を
                    // 入力欄の実測高さに合わせてTweenAnimationBuilderで
                    // アニメーションさせることで、入力欄が伸び縮みする際に
                    // メッセージがその下へ滑らかに潜り込むように見せている
                    // （2026-07-30、入力欄の直前でメッセージが唐突に
                    // 途切れて見える不具合の修正）。

                    // 読み込み済みの内容が画面を埋めきらない（＝そもそも
                    // スクロールする余地が無い）場合、ユーザーのスクロール
                    // 操作を待つ`_maybeLoadOlderMessages`（スクロール通知
                    // 起点）が一切発火しない。フレーム描画後にその状態を
                    // 検知し、スクロール無しでも自動的に次の日を読み込む
                    // （2026-08-21、直近日のメッセージ数が少ない語らいで
                    // 過去日が全く読み込まれない不具合の修正）。
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _maybeLoadOlderMessages();
                    });

                    return TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        end: (_selecting || _screenshotSelecting)
                            ? 0
                            : _composerAreaHeight,
                      ),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      builder: (context, bottomInset, _) =>
                          ScrollablePositionedList.builder(
                            itemScrollController: _itemScrollController,
                            itemPositionsListener: _itemPositionsListener,
                            reverse: true,
                            itemCount: reversedEntries.length,
                            itemBuilder: (context, index) =>
                                reversedEntries[index],
                            padding: EdgeInsets.fromLTRB(
                              12,
                              12,
                              12,
                              12 + bottomInset,
                            ),
                          ),
                    );
                  },
                ),
                if (!_selecting &&
                    !_screenshotSelecting &&
                    widget.onSend != null)
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
                              vocabulary: vocabulary,
                            ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // ＋ボタン（技術仕様書5.6参照）。左端に配置し、
                                  // 送信ボタンとは反対側に置くことでタップ位置を
                                  // 明確に分ける（2026-08-10変更、以前はテキスト欄の
                                  // 右・送信ボタンの左にあった）。TextFieldの
                                  // suffixIconとして持たせると、TextField自身が
                                  // 持つタップ検出（ジェスチャーアリーナに
                                  // 参加しない`Listener`ベースの独自実装と
                                  // 競合しない側）がこのタップも検出してしまい、
                                  // ソフトウェアキーボードが開いてポップアップの
                                  // 表示位置がズレる不具合があったため、TextFieldの
                                  // 外（Rowの兄弟要素）に出している。
                                  if (widget.onSendAttachment != null &&
                                      !widget.disabled)
                                    AttachmentPopupButton(
                                      strings: strings,
                                      isGekiga: isGekiga,
                                      onPicked: _handleAttachmentPicked,
                                      stickerLabel: vocabulary?.sticker,
                                      onStickerPicked:
                                          widget.onSendSticker == null
                                          ? null
                                          : _handleStickerPicked,
                                    ),
                                  Expanded(
                                    child: Focus(
                                      onKeyEvent: _handleKeyEvent,
                                      child: isGekiga
                                          ? _GekigaComposerField(
                                              // ペタピタアイコンを固定位置に
                                              // 保つため、Stack+Positioned
                                              // （確定後サイズを基準に位置
                                              // 決めする間接的な仕組み）は
                                              // 狙った通りに動かなかったため
                                              // 撤回し、Row+
                                              // CrossAxisAlignment.endに
                                              // 変更した（2026-08-12修正、
                                              // 当初.startとしていたのは
                                              // 誤りだったため再修正）。
                                              // 入力欄コンテナ自体は画面下端
                                              // にPositioned(bottom: 0)で
                                              // 固定されており、行数が増える
                                              // とボックスは上方向にしか
                                              // 伸びない。そのため固定48×48
                                              // のアイコンをRowの下端に揃え
                                              // れば、アイコンの絶対位置は
                                              // 行数によらず常に変化しない
                                              // （逆に上揃えだと、行が増える
                                              // たびにアイコンが上へ動いて
                                              // しまっていた）。
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Expanded(
                                                    // Rowが.end（下揃え）の
                                                    // ため、1行だけの場合
                                                    // TextField自身の高さが
                                                    // 48×48のアイコンより
                                                    // 低いと、その差分だけ
                                                    // TextFieldの上に空白が
                                                    // でき、textAlignVertical
                                                    // .centerで中央寄せして
                                                    // いても見た目上は下寄り
                                                    // に見えていた
                                                    // （2026-08-12修正）。
                                                    // 最小高さをアイコンと
                                                    // 揃えることで、1行の
                                                    // 時もアイコンと同じ
                                                    // 48px基準で縦中央に
                                                    // なるようにする。
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            minHeight: 48,
                                                          ),
                                                      child: TextField(
                                                        controller:
                                                            _textController,
                                                        focusNode:
                                                            _composerFocusNode,
                                                        enabled:
                                                            !widget.disabled,
                                                        minLines: 1,
                                                        maxLines: 6,
                                                        textAlignVertical:
                                                            TextAlignVertical
                                                                .center,
                                                        textInputAction:
                                                            TextInputAction
                                                                .newline,
                                                        keyboardType:
                                                            TextInputType
                                                                .multiline,
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                        ),
                                                        cursorColor:
                                                            Colors.black,
                                                        decoration: InputDecoration(
                                                          hintText: strings
                                                              .chatInputHint,
                                                          hintStyle: TextStyle(
                                                            color: Colors.black
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                          ),
                                                          filled: false,
                                                          border:
                                                              InputBorder.none,
                                                          enabledBorder:
                                                              InputBorder.none,
                                                          focusedBorder:
                                                              InputBorder.none,
                                                          // 内容量に応じて
                                                          // 箱の高さがぴったり
                                                          // 詰まるため、上下に
                                                          // 8pxの余白を確保
                                                          // して文字が上端に
                                                          // 張り付いて見え
                                                          // ないようにする。
                                                          // 水平方向も明示
                                                          // しないと0pxに
                                                          // なり左端に文字が
                                                          // 寄って見えていた
                                                          // ため、4pxを確保
                                                          // する
                                                          // （2026-08-12修正）。
                                                          contentPadding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 4,
                                                                vertical: 8,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (widget.onSendSticker !=
                                                          null &&
                                                      !widget.disabled)
                                                    SizedBox(
                                                      width: 48,
                                                      height: 48,
                                                      child:
                                                          _stickerComposerButton(
                                                            isGekiga: true,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            )
                                          : Stack(
                                              children: [
                                                TextField(
                                                  controller: _textController,
                                                  focusNode: _composerFocusNode,
                                                  enabled: !widget.disabled,
                                                  minLines: 1,
                                                  maxLines: 6,
                                                  textAlignVertical:
                                                      const TextAlignVertical(
                                                        y: 0.4,
                                                      ),
                                                  textInputAction:
                                                      TextInputAction.newline,
                                                  keyboardType:
                                                      TextInputType.multiline,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        strings.chatInputHint,
                                                    filled: widget.disabled,
                                                    fillColor: Theme.of(context)
                                                        .disabledColor
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                    ),
                                                    // suffixIconは既定で常に
                                                    // 縦中央揃えになり、複数
                                                    // 行になるほど絶対位置が
                                                    // 動いてしまう。実アイコン
                                                    // はStack最前面のPositioned
                                                    // （下揃え固定）で描くため、
                                                    // ここでは同じ横幅48pxだけ
                                                    // を確保するダミーにする
                                                    // （2026-08-12修正）。
                                                    suffixIcon:
                                                        widget.onSendSticker !=
                                                                null &&
                                                            !widget.disabled
                                                        ? const SizedBox(
                                                            width: 48,
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                                if (widget.onSendSticker !=
                                                        null &&
                                                    !widget.disabled)
                                                  Positioned(
                                                    bottom: 0,
                                                    right: 4,
                                                    height: 48,
                                                    child:
                                                        _stickerComposerButton(
                                                          isGekiga: false,
                                                        )!,
                                                  ),
                                              ],
                                            ),
                                    ),
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
                                            // タップでこのボタン自身が
                                            // フォーカスを奪うと、テキスト欄が
                                            // フォーカスを失いモバイルで
                                            // ソフトウェアキーボードが閉じて
                                            // しまうため、フォーカス移動を
                                            // 抑制する（2026-08-12）。
                                            canRequestFocus: false,
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
    this.vocabulary,
  });

  final Message? replyingTo;
  final bool editing;
  final Strings strings;
  final VoidCallback onCancel;

  /// 返信先がペタピタの場合の固定文言に使う（[_MessageRow.vocabulary]と
  /// 同じ理由でnullableにしている、2026-08-13追加）。
  final Vocabulary? vocabulary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final replying = replyingTo;
    final thumbnail = replying != null
        ? _replyPreviewThumbnail(replying)
        : null;
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
                          replying?.senderRhingId != null
                              ? '@${replying!.senderRhingId}'
                              : '?',
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        replying != null
                            ? _replySnippetLabel(replying, vocabulary)
                            : '',
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
          if (!editing && thumbnail != null) ...[
            const SizedBox(width: 4),
            thumbnail,
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
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
/// 返信引用プレビューのラベル文言。ペタピタは技術的な`content`
/// （スタンプ名、コードのように見える）をそのまま出さず、固定の用語
/// （[Vocabulary.sticker]）に置き換える（2026-08-13追加）。
/// [showStickerPickerPopup]のアンカー矩形を、与えられた[context]が属する
/// ウィジェットの画面上の位置・サイズから計算する（2026-08-14追加）。
/// 送信アイコン（永続的な`GlobalKey`経由）・メッセージ上のペタピタタップ
/// （タップ時点の`BuildContext`をそのまま利用）の両方から共通で使う。
Rect _anchorRectFromContext(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

String _replySnippetLabel(Message target, Vocabulary? vocabulary) {
  if (target.contentType == 'sticker') {
    return vocabulary?.sticker ?? 'ペタピタ';
  }
  return messageSnippetOf(target.content);
}

/// 返信引用プレビューの右隣に添える小さいサムネイル（32x32）。
/// ペタピタ・画像・動画とも実際のサムネイルを表示する（動画は`_VideoThumbnail`
/// の正方形モードを流用、2026-08-14。画面内に同時に見える「動画への返信」は
/// 多くても数件程度で、`_VideoThumbnail`自体がController初期化・破棄を
/// 完結させる作りのため、本文側の動画表示と比べて追加コストは無い）。
/// それ以外のcontentTypeではnullを返す。
Widget? _replyPreviewThumbnail(Message target) {
  const size = 32.0;
  switch (target.contentType) {
    case 'sticker':
      final url = target.stickerData?.stickerUrl;
      if (url == null) return null;
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    case 'image':
      final url = target.fileMetadata?.url;
      if (url == null) return null;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    case 'video':
      final url = target.fileMetadata?.url;
      if (url == null) return null;
      // video_playerはiOS/Android/Web/macOSのみ対応（Linux/Windowsは
      // 非対応、技術仕様書5.8参照）。メッセージ本文側の動画表示
      // （`_attachmentContent`）と同じ判定式。
      final supportsInAppPlayback =
          kIsWeb || !(Platform.isWindows || Platform.isLinux);
      return _VideoThumbnail(
        url: url,
        canLoad: supportsInAppPlayback,
        size: size,
      );
    default:
      return null;
  }
}

class _MessageRow extends ConsumerWidget {
  const _MessageRow({
    required this.message,
    required this.isMe,
    required this.currentUserId,
    required this.timeLabel,
    required this.colorScheme,
    required this.floatingShadow,
    this.uiStyle = AppUiStyle.flat,
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
    this.mediaMessages = const [],
    this.onReply,
    this.onEdit,
    this.onUnsend,
    this.onSetReaction,
    this.onJumpToReply,
    this.onSendSticker,
    this.stickerButtonKey,
    this.highlighted = false,
    this.timeFormat = MessageTimeFormat.h24,
    this.onDeclineAccountDeletionNotice,
    this.onDeleteAfterAccountDeletion,
    this.onSwipeBack,
    this.vocabulary,
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

  /// 現在ロード済みのメッセージのうち、画像/動画のみを古い順に並べたもの。
  /// 画像/動画の拡大表示（`_MediaViewerScreen`）で、前後スワイプ・矢印キー
  /// ナビゲーション対象の一覧として使う（`_attachmentContent`参照、
  /// 2026-08-14追加）。
  final List<Message> mediaMessages;

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

  /// 他人が送信済みのペタピタをタップし、自分も所持しているパックだった
  /// 場合にそのパックから選び直して送信する導線で使う（[_stickerContent]
  /// 参照、2026-08-14追加）。nullなら送信機能自体を出さない
  /// （[ChatScreen.onSendSticker]がnullの読み取り専用画面等）。
  final Future<void> Function(Sticker sticker)? onSendSticker;

  /// 送信用の専用ペタピタアイコン（`_ChatScreenState._stickerButtonKey`）の
  /// `GlobalKey`。所持ペタピタタップ時に開くポップアップの座標を、送信
  /// アイコンクリック時（[ChatScreen]の`_openStickerPicker`）と完全に
  /// 一致させるため、`_handleStickerTap`のアンカー計算にそのまま使う
  /// （2026-08-14追加）。送信アイコン自体が無い画面ではnull（その場合は
  /// ボトムシートにフォールバックする）。
  final GlobalKey? stickerButtonKey;

  /// 返信先ジャンプ直後、対象メッセージだと分かるよう一瞬背景を強調する。
  final bool highlighted;

  /// contentType='call'（通話サマリー）の開始時刻表示に使う時刻表示形式。
  final MessageTimeFormat timeFormat;

  /// contentType='accountDeleted'通知への「いいえ」。DMのみ渡される。
  final Future<void> Function(String messageId)? onDeclineAccountDeletionNotice;

  /// contentType='accountDeleted'通知への「はい」（確認ダイアログの上で
  /// 呼ばれる）。DMのみ渡される。
  final Future<void> Function()? onDeleteAfterAccountDeletion;

  /// 縦表示で、吹き出しの上を右スワイプした時に会話一覧へ戻る処理
  /// ([ChatScreen.onSwipeBack]参照)。右寄せ表示（自分のメッセージ・
  /// sideBySideレイアウト）ではこの挙動を除外する
  /// （`_MessageInteractions`側で判定）。
  final VoidCallback? onSwipeBack;

  /// 返信引用プレビュー内のペタピタ固定文言（[Vocabulary.sticker]）に使う。
  /// nullの場合は標準の用語（「ペタピタ」）にフォールバックする
  /// （2026-08-13追加。テストの素朴な`ChatScreen`構築や`onSendSticker`が
  /// nullの読み取り専用画面等、`vocabularyProvider`の購読自体を避けたい
  /// 呼び出し元向けに、呼び出し元（`_ChatScreenState.build`）で計算済みの
  /// 値を渡してもらう設計にしている）。
  final Vocabulary? vocabulary;

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
          ? _replySnippetLabel(target, vocabulary)
          : (message.replyToSnippet ?? '');
      final thumbnail = target != null ? _replyPreviewThumbnail(target) : null;
      if (replySenderId != null) {
        final quoteBox = Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: onBubbleColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          // mainAxisSize: MainAxisSize.min（既定のmaxのままだと、送信者名や
          // スニペットが短くても親から渡された最大幅いっぱいに引き伸ばされ、
          // サムネイル導入時に横幅が不必要に広く見える不具合があった、
          // 2026-08-14対応）。テキスト列もExpandedではなくFlexibleにして、
          // 短い内容ならボックス自体が縮むようにする（長い内容は既存の
          // maxLines: 1 + ellipsisで従来通り省略表示される）。
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SenderName(
                      userId: replySenderId,
                      rhingId: replySenderRhingId,
                      conversationId: conversationId,
                      color: onBubbleColor,
                    ),
                    Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: onBubbleColor),
                    ),
                  ],
                ),
              ),
              if (thumbnail != null) ...[const SizedBox(width: 4), thumbnail],
            ],
          ),
        );
        // 返信先へのジャンプは、この引用プレビュー自体にだけタップを
        // 割り当てる（2026-08-12変更）。以前は吹き出し全体
        // （_MessageBubbleTapArea）にタップを割り当てていたが、画像/動画
        // 本体（タップでフルスクリーン表示）やURLリンク（LinkifiedTextの
        // TapGestureRecognizer）と吹き出し内でジェスチャーの取り合いになり、
        // 最も内側の認識者が優先されるFlutterの仕様上、ジャンプが発火しない
        // ことがあった（タップ位置次第で結果が変わって見えていた不具合の
        // 主因）。
        final targetId = message.replyToMessageId;
        replyPreview = (targetId != null && onJumpToReply != null)
            ? InkWell(
                onTap: () => onJumpToReply!(targetId),
                borderRadius: BorderRadius.circular(8),
                child: quoteBox,
              )
            : quoteBox;
      }
    }

    final isCallSummary = message.contentType == 'call';
    final isAccountDeletedNotice = message.contentType == 'accountDeleted';
    final isSticker = message.contentType == 'sticker';
    final isAttachment =
        message.contentType == 'file' ||
        message.contentType == 'image' ||
        message.contentType == 'video';
    // マークダウンプレビューカード（`_FileAttachmentBlock`）は自前の枠
    // （`GekigaJointedTileList`）を持つため、`_GekigaBubble`側の枠は
    // 二重表示になる（2026-08-10、ユーザー指摘により画像と同じ扱いにした）。
    final isMarkdownPreview =
        message.contentType == 'file' &&
        message.fileMetadata != null &&
        _FileAttachmentBlock.isPreviewableMarkdown(message.fileMetadata!);

    final bubbleContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?replyPreview,
        if (isCallSummary)
          _callSummaryContent(onBubbleColor)
        else if (isAccountDeletedNotice)
          _accountDeletedContent(context, ref, strings, onBubbleColor, isGekiga)
        else if (isAttachment)
          _attachmentContent(context, onBubbleColor, isGekiga)
        else if (isSticker)
          _stickerContent(context, ref, onBubbleColor)
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
            skipFrame:
                message.contentType == 'image' ||
                message.contentType == 'video' ||
                isMarkdownPreview ||
                isSticker,
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
              if (previewUrl != null)
                LinkPreviewCard(url: previewUrl, isGekiga: isGekiga),
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
                    if (previewUrl != null)
                      LinkPreviewCard(url: previewUrl, isGekiga: isGekiga),
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
  /// （技術仕様書5.2・5.6・5.8参照、2026-08-10追加、2026-08-11に動画の
  /// アプリ内再生を追加）。画像・動画はサムネイル/プレースホルダーを直接
  /// 表示しタップで全画面表示、ファイルはアイコン+ファイル名+サイズを
  /// 表示しタップでブラウザ等の外部アプリで開く。
  /// ペタピタ（スタンプ）メッセージの表示。LINE/Discord等の一般的な
  /// 見せ方に合わせ、吹き出し枠・劇画モノクロ枠（[skipFrame]参照）を
  /// 付けずに単体の画像として表示する（技術仕様書7.4参照、2026-08-11追加）。
  /// タップすると、自分が所持しているパックのペタピタならそのパックに
  /// 絞り込んだ送信ピッカーを開き、未所持ならdaidai横丁のストアページを
  /// ブラウザの別タブで開く（daidai横丁自体はアプリ内に持たない方針の
  /// ため、Apple/Google手数料回避と軽量化を兼ねる、2026-08-14追加）。
  /// 自分が送信したペタピタも同じ経路で開ける（所持パックからしか送信
  /// できない仕様上、常に「所持している」分岐に入る）。
  Widget _stickerContent(
    BuildContext context,
    WidgetRef ref,
    Color onBubbleColor,
  ) {
    final stickerData = message.stickerData;
    if (stickerData == null) {
      return Text(message.content, style: TextStyle(color: onBubbleColor));
    }
    return GestureDetector(
      onTap: () => _handleStickerTap(context, ref, stickerData),
      child: Image.network(
        stickerData.stickerUrl,
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.broken_image_outlined, color: onBubbleColor),
      ),
    );
  }

  Future<void> _handleStickerTap(
    BuildContext context,
    WidgetRef ref,
    MessageStickerData stickerData,
  ) async {
    final strings = ref.read(appStringsProvider);
    final stickerRepository = ref.read(stickerRepositoryProvider);
    final packId = await stickerRepository.findPackIdForSticker(
      stickerData.stickerId,
    );
    if (!context.mounted) return;
    if (packId == null) {
      showAutoDismissBanner(
        context,
        message: strings.stickerPackNotFoundMessage,
      );
      return;
    }

    final owned = await stickerRepository.ownsPack(currentUserId, packId);
    if (!context.mounted) return;

    if (owned) {
      final onSendStickerCallback = onSendSticker;
      if (onSendStickerCallback == null) return;
      // 送信用の専用ペタピタアイコン（`_openStickerPicker`）と同じ幅分岐・
      // 同じアンカー座標を使う（`stickerButtonKey`＝`_stickerButtonKey`を
      // そのまま参照するため、表示位置が送信アイコンクリック時と完全に
      // 一致する。デスクトップ幅はそのアイコン付近のポップアップ、
      // モバイル幅はボトムシート、2026-08-14）。
      final isWide = MediaQuery.sizeOf(context).width >= kTalksSplitBreakpoint;
      final anchorContext = stickerButtonKey?.currentContext;
      final sticker = (isWide && anchorContext != null)
          ? await showStickerPickerPopup(
              context,
              anchorRect: _anchorRectFromContext(anchorContext),
              initialPackId: packId,
            )
          : await showModalBottomSheet<Sticker>(
              context: context,
              isScrollControlled: true,
              builder: (_) => StickerPickerSheet(initialPackId: packId),
            );
      if (sticker == null) return;
      await onSendStickerCallback(sticker);
      return;
    }

    // Apple/Googleからのアクセスのみ手数料上乗せ価格を表示する想定
    // （実際の値付け・表示ロジックはdaidai横丁のストアページ側＝この
    // リポジトリ外で実装、technical spec参照）。既存の動画再生対応判定
    // （3184行目付近）と同じ書き方でプラットフォームを判定する。
    final platform = kIsWeb
        ? 'web'
        : Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : 'other';
    final storeUri = Uri.parse(
      'https://rhing.jp/daidai-yokocho/$packId?platform=$platform',
    );
    await launchUrl(storeUri, mode: LaunchMode.externalApplication);
  }

  Widget _attachmentContent(
    BuildContext context,
    Color onBubbleColor,
    bool isGekiga,
  ) {
    final metadata = message.fileMetadata;
    if (metadata == null) {
      return Text(message.content, style: TextStyle(color: onBubbleColor));
    }

    if (message.contentType == 'image') {
      final image = Image.network(
        metadata.url,
        width: 280,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Icon(Icons.broken_image_outlined, color: onBubbleColor),
      );
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _MediaViewerScreen(
              mediaMessages: mediaMessages,
              initialIndex: mediaMessages.indexWhere(
                (m) => m.messageId == message.messageId,
              ),
            ),
          ),
        ),
        child: mediaPreviewFrame(isGekiga: isGekiga, child: image),
      );
    }

    if (message.contentType == 'video') {
      // video_playerはiOS/Android/Web/macOSのみ対応（Linux/Windowsは
      // 非対応、技術仕様書5.8参照）。attachment_upload.dartの
      // 既存プラットフォーム分岐と同じパターンで判定する。
      final supportsInAppPlayback =
          kIsWeb || !(Platform.isWindows || Platform.isLinux);
      return GestureDetector(
        onTap: () => supportsInAppPlayback
            ? Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _MediaViewerScreen(
                    mediaMessages: mediaMessages,
                    initialIndex: mediaMessages.indexWhere(
                      (m) => m.messageId == message.messageId,
                    ),
                  ),
                ),
              )
            : launchUrl(
                Uri.parse(metadata.url),
                mode: LaunchMode.externalApplication,
              ),
        child: mediaPreviewFrame(
          isGekiga: isGekiga,
          child: _VideoThumbnail(
            url: metadata.url,
            canLoad: supportsInAppPlayback,
          ),
        ),
      );
    }

    return _FileAttachmentBlock(
      metadata: metadata,
      onBubbleColor: onBubbleColor,
      isGekiga: isGekiga,
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
    bool isGekiga,
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
                // colorScheme.errorはダークテーマ下ではMaterial3の仕様上
                // 明るめのサーモンピンクに近い色になり、白文字が読みにくく
                // なるため使わない（CLAUDE.mdのボタン配色ルール参照、
                // 2026-08-12）。
                style: isGekiga
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black, width: 2),
                      )
                    : FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
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
            // group_delete_dialog.dart等、他の削除確認ダイアログと同じ
            // 固定の濃い赤に揃える（colorScheme.errorはダークテーマ下では
            // 明るいサーモンピンクになり白文字が読みにくいため使わない、
            // CLAUDE.mdのボタン配色ルール参照、2026-08-12）。
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
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

    // 長押し座標そのものにメニューの左上を合わせると指がメニューに重なって
    // 選びにくいため、＋ボタンの添付ポップアップ（AttachmentPopupButton.
    // _onPointerDown）と同じく、押した座標より少し上に離して表示する
    // （2026-08-11変更）。
    const screenPad = 8.0;
    final left = details.globalPosition.dx.clamp(
      screenPad,
      screenSize.width - menuWidth - screenPad,
    );
    final top = (details.globalPosition.dy - menuHeight - 8).clamp(
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
    _highlightIndex.value = -1;

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

/// 左スワイプ（軽く=返信、最後まで=編集。編集は[canEdit]がtrueの時のみ）を
/// 扱う。メニューを開く長押し/右クリックは吹き出し本体
/// （[_MessageBubbleTapArea]）側に分離済み（2026-07-29変更）。吹き出し横の
/// 余白の長押しによる自動スクロールは2026-08-12に、ミドルクリックによる
/// 自動スクロールは2026-08-20に、それぞれ廃止した。
/// 選択モード中（[ChatScreen]の範囲選択削除）は使わない（_MessageRow.build参照）。
class _MessageInteractions extends StatefulWidget {
  const _MessageInteractions({
    required this.child,
    required this.canEdit,
    required this.onReply,
    this.onEdit,
    this.onSwipeBack,
    this.alignRight = false,
  });

  final Widget child;
  final bool canEdit;
  final VoidCallback onReply;
  final VoidCallback? onEdit;

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
    this.uiStyle = AppUiStyle.flat,
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

/// 添付画像・動画メッセージのサムネイルをタップした時の全画面表示
/// （[_MessageRow._attachmentContent]参照、2026-08-10追加、2026-08-14に
/// 前後スワイプ・矢印キーでのナビゲーション対応に伴い[_ImageViewerScreen]/
/// [_VideoViewerScreen]から統合）。[mediaMessages]（同じ語らい内の画像/動画
/// メッセージを古い順に並べたもの、[_MessageRow.mediaMessages]参照）を
/// `PageView`でめくる。右スワイプ（＝`PageView`の前ページ方向）で前
/// （古い方）、左スワイプで後（新しい方）に切り替わる。コンピューターでは
/// 矢印キーでも同様に操作できる。動画は、最初に開いた対象（[initialIndex]）
/// のときだけ自動再生し、スワイプ/矢印キーで切り替えた先の動画は自動再生
/// せず、中央の再生ボタンをタップして再生を始める（[_VideoViewerPage]参照）。
class _MediaViewerScreen extends StatefulWidget {
  const _MediaViewerScreen({
    required this.mediaMessages,
    required this.initialIndex,
  });

  final List<Message> mediaMessages;
  final int initialIndex;

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late final int _safeInitialIndex = widget.initialIndex.clamp(
    0,
    widget.mediaMessages.length - 1,
  );
  late final PageController _pageController = PageController(
    initialPage: _safeInitialIndex,
  );
  late int _currentIndex = _safeInitialIndex;

  // 動画ページの`GlobalKey`（messageId基準）。スペースキーで現在表示中の
  // 動画の再生/一時停止をトグルするために、`_VideoViewerPageState`へ
  // 直接アクセスする（2026-08-14追加）。`PageView.builder`のindexではなく
  // messageIdをキーにするのは、ウィジェット自身の`key:`としても兼用し、
  // スワイプ中の内部再構築でも同じ`_VideoViewerPageState`（＝
  // `VideoPlayerController`）が保たれるようにするため（GlobalKeyはツリー内
  // での位置に関わらず同一のStateを保持し続ける）。
  final Map<String, GlobalKey<_VideoViewerPageState>> _videoPageKeys = {};

  static const _pageChangeDuration = Duration(milliseconds: 200);

  // マウスホイール/トラックパッドでの下スクロール終了のデバウンス用
  // タイマー（2026-08-19追加、下記onPointerSignal参照）。
  Timer? _scrollDismissTimer;

  @override
  void dispose() {
    _scrollDismissTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// `f`キーでのブラウザ本来の全画面表示トグル（[fullscreen.dart]参照、
  /// 2026-08-18追加）。Web以外ではstub実装が何もしないため無害。
  Future<void> _toggleFullscreen() async {
    if (isDocumentFullscreen) {
      await exitDocumentFullscreen();
    } else {
      await requestDocumentFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        // メッセージ画面へ戻るボタン（2026-08-14、明示化）。
        // `AppBar`の自動`leading`（`automaticallyImplyLeading`）に任せず
        // 明示的に`Navigator.pop`を指定する。
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Escキー・矢印キー（コンピューター向け前後ナビゲーション、
      // 2026-08-14追加）・スペースキー（現在表示中の動画の再生/一時停止、
      // 2026-08-14追加）・下スワイプで一覧画面へ戻れるようにする
      // （Escキー・下スワイプは2026-08-11から踏襲）。
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _pageController.previousPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _pageController.nextPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space) {
            final currentMessageId =
                widget.mediaMessages[_currentIndex].messageId;
            _videoPageKeys[currentMessageId]?.currentState?._togglePlayback();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            _toggleFullscreen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        // マウスホイール/トラックパッドで上方向へスクロールしただけで
        // 閉じられるようにする（2026-08-19追加、ドラッグ操作は不要。
        // 同日、PCのみ方向をユーザー指示で反転）。モバイルのフリックに
        // よる`SwipeDownToDismiss`はそのまま維持し、その外側にスクロール
        // 検出用の`Listener`を重ねるだけに留める。
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
              // トラックパッドの2本指スワイプ等は1回の操作で多数の
              // PointerScrollEventが連続して届く。即座にpop()すると、
              // 同じジェスチャーの残りのイベントがpop後の最前面ルート
              // （メッセージ画面）へ漏れて、その分だけ意図せず
              // スクロールされてしまう不具合があった（2026-08-19判明）。
              // 新しいスクロールイベントが来るたびタイマーを延長し、
              // 一定時間（150ms）イベントが来なくなってからpop()する
              // ことで、ジェスチャー全体をこのListenerが確実に消費
              // しきってから閉じるようにする。
              _scrollDismissTimer?.cancel();
              _scrollDismissTimer = Timer(
                const Duration(milliseconds: 150),
                () {
                  if (mounted) Navigator.of(context).pop();
                },
              );
            }
          },
          child: SwipeDownToDismiss(
            onDismiss: () => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaMessages.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final message = widget.mediaMessages[index];
                final url = message.fileMetadata?.url ?? '';
                if (message.contentType == 'video') {
                  return _VideoViewerPage(
                    key: _videoPageKeys.putIfAbsent(
                      message.messageId,
                      GlobalKey<_VideoViewerPageState>.new,
                    ),
                    url: url,
                    autoPlay: index == _safeInitialIndex,
                  );
                }
                return _ImageViewerPage(url: url);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// [_MediaViewerScreen]の1ページ分（画像）。Escキー・下スワイプ・
/// 画面全体の`Scaffold`/`AppBar`は[_MediaViewerScreen]側が共通で持つため、
/// ここでは画像本体と「画像以外の箇所のタップで閉じる」ジェスチャーのみを
/// 持つ（2026-08-10追加、2026-08-14に[_MediaViewerScreen]への統合に伴い
/// [_ImageViewerScreen]から改名）。内側のGestureDetectorは何もしないonTapで
/// タップを吸収し、画像自体をタップした際に外側へ伝播して閉じてしまうのを
/// 防ぐ。画像をズームしてパン中はInteractiveViewer側のジェスチャーが
/// 優先されるため誤って閉じない。
class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
    );
  }
}

/// 動画添付メッセージのインラインプレビュー（[_MessageRow._attachmentContent]
/// 参照、2026-08-11追加、技術仕様書5.8参照）。画像と同様に実際の最初の
/// コマを表示する（当初は暗いプレースホルダーのみだったが、ユーザー要望
/// により変更）。実現には別途サムネイル生成パッケージ（`video_thumbnail`
/// 等、Android/iOSのみ対応）を使わず、既に導入済みの`video_player`で
/// `VideoPlayerController`を初期化した直後（`play()`を呼ばない、＝先頭
/// フレームで一時停止した状態）の`VideoPlayer`ウィジェットをそのまま
/// 表示する。`canLoad`がfalse（Linux/Windows、`video_player`非対応）の
/// 場合は読み込み自体を行わず、暗いプレースホルダーのままにする。
class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url, required this.canLoad, this.size});

  final String url;
  final bool canLoad;

  /// 指定時は`size`×`size`の正方形（`BoxFit.cover`でクロップ）で表示する
  /// （返信引用プレビュー用、2026-08-14追加）。未指定なら既存の280px固定＋
  /// アスペクト比維持のレターボックス表示（メッセージ本文の添付表示用）。
  final double? size;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!widget.canLoad) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
        .initialize()
        .then((_) {
          if (mounted) setState(() => _ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  static const _playIcon = Center(
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final squareSize = widget.size;
    if (squareSize != null) {
      // 正方形モード（返信引用プレビュー）。アスペクト比を維持したレター
      // ボックスではなく、ボックスいっぱいにクロップして小さいサムネイルとして
      // 見やすくする。
      final content = _ready && controller != null
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          : Container(color: Colors.black87);
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: squareSize,
          height: squareSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Icon(Icons.play_arrow, color: Colors.white, size: squareSize / 2),
            ],
          ),
        ),
      );
    }
    if (_ready && controller != null) {
      return SizedBox(
        width: 280,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [VideoPlayer(controller), _playIcon],
          ),
        ),
      );
    }
    return SizedBox(
      width: 280,
      height: 280 * 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black87),
          _playIcon,
        ],
      ),
    );
  }
}

/// [_MediaViewerScreen]の1ページ分（動画）。Escキー・下スワイプ・
/// 画面全体の`Scaffold`/`AppBar`は[_MediaViewerScreen]側が共通で持つため、
/// ここでは動画本体・再生コントロールのみを持つ（2026-08-11追加、
/// 2026-08-14に[_MediaViewerScreen]への統合に伴い[_VideoViewerScreen]から
/// 改名）。`video_player`はiOS/Android/Web/macOSのみ対応のため、
/// Linux/Windowsではこの画面を開かず外部アプリで開く（呼び出し元の
/// `_attachmentContent`側で分岐済み）。[autoPlay]がtrueの時だけ初期化後に
/// 自動再生する（チャットのプレビューから直接開いた対象のみtrue。
/// スワイプ/矢印キーで切り替えた先はfalseになり、中央の再生ボタン
/// （[_CenterPlayButton]）をタップするまで一時停止のまま、2026-08-14追加）。
/// 再生/一時停止は、動画の座標上（レターボックスの余白含む）のどこを
/// タップしても、またスペースキーでも切り替えられる（[_togglePlayback]、
/// スペースキーは[_MediaViewerScreen]の`Focus`から`GlobalKey`経由で
/// 呼び出す、2026-08-14追加）。
class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({
    super.key,
    required this.url,
    required this.autoPlay,
  });

  final String url;
  final bool autoPlay;

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;

  /// 中央の再生/一時停止＋10秒送り/戻しボタンの表示状態
  /// （2026-08-18追加）。一時停止中は常時`true`（`build`側で
  /// `!isPlaying`と合わせて判定）、再生中はポインター移動のたびに
  /// `_resetControlsVisibility`で`true`に戻り、[_hideTimer]で数秒後に
  /// `false`へフェードアウトする。
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// シークバーのドラッグ中だけ使うローカルの再生位置（ミリ秒、
  /// 2026-08-18追加）。ドラッグ中は`ValueListenableBuilder`が拾う
  /// `_controller`側の位置と競合させず、この値をそのまま`Slider`へ
  /// 表示する。ドラッグ終了で`null`に戻す。
  double? _dragPositionMs;

  /// モバイル限定のダブルタップ10秒送り/戻し操作時に表示する
  /// フラッシュ文言（`+10秒`/`−10秒`、2026-08-18追加）。
  String? _skipFlashLabel;
  Timer? _skipFlashTimer;

  /// ダブルタップでの10秒送り/戻しをモバイル（Android/iOS）限定にする
  /// 判定（2026-08-18追加）。デスクトップ/Webで`onDoubleTapDown`を
  /// 常設すると、既存の動画本体クリック（`onTap: _togglePlayback`）が
  /// ダブルタップ判定待ちのため約300ms遅延してしまうため、モバイル以外
  /// では`onDoubleTapDown`自体を渡さない。
  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializeFuture = _controller.initialize().then((_) {
      if (widget.autoPlay) _controller.play();
      if (mounted) setState(() {});
      _resetControlsVisibility();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipFlashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
    _resetControlsVisibility();
  }

  /// 中央コントロールを表示状態にし、再生中なら数秒後に自動的に
  /// 非表示へ戻すタイマーを（張り直して）セットする（2026-08-18追加）。
  /// 一時停止中はタイマーをセットしない（`build`側の`!isPlaying`判定で
  /// 常時表示になるため）。ポインター移動・タップでの再生/一時停止・
  /// 10秒送り/戻し操作のたびに呼び出す。
  void _resetControlsVisibility() {
    _hideTimer?.cancel();
    _hideTimer = null;
    setState(() => _controlsVisible = true);
    if (_controller.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  /// 再生位置を[offset]分早送り/巻き戻しする（2026-08-14追加、
  /// `_buildControlBar`の10秒送り/戻しボタンで使う）。0秒〜動画の長さの
  /// 範囲にクランプする。`_controller`は`ValueNotifier`なので、
  /// `seekTo`後の位置反映は`_buildControlBar`の`ValueListenableBuilder`が
  /// 自動的に拾う（setState不要）。
  void _skip(Duration offset) {
    final target = _controller.value.position + offset;
    final duration = _controller.value.duration;
    _controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : (target > duration ? duration : target),
    );
  }

  /// モバイル限定のダブルタップ操作（2026-08-18追加）。タップ位置が
  /// 動画エリア（[areaWidth]、レターボックス含む）の右半分なら10秒送り、
  /// 左半分なら10秒戻し、あわせて[_showSkipFlash]で一瞬のフラッシュ表示。
  void _handleDoubleTapSkip(TapDownDetails details, double areaWidth) {
    final isRightHalf = details.localPosition.dx > areaWidth / 2;
    _skip(Duration(seconds: isRightHalf ? 10 : -10));
    _showSkipFlash(forward: isRightHalf);
    _resetControlsVisibility();
  }

  /// 「+10秒」「−10秒」を一瞬フラッシュ表示する（2026-08-18追加）。
  void _showSkipFlash({required bool forward}) {
    _skipFlashTimer?.cancel();
    setState(() => _skipFlashLabel = forward ? '+10秒' : '−10秒');
    _skipFlashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _skipFlashLabel = null);
    });
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 再生/一時停止ボタン・現在位置/合計時間・白色のプログレスバー
  /// （2026-08-11追加）。再生位置は再生中も連続的に進むため、`_controller`
  /// （それ自体が`ValueNotifier<VideoPlayerValue>`）を`ValueListenableBuilder`
  /// で購読し、位置・再生状態の変化のたびに再描画する。
  Widget _buildControlBar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds.toDouble();
        final sliderMax = durationMs <= 0 ? 1.0 : durationMs;
        final sliderValue =
            (_dragPositionMs ?? value.position.inMilliseconds.toDouble()).clamp(
              0.0,
              sliderMax,
            );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                _formatDuration(value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                // 現在の再生位置に丸（つまみ）を表示し、ドラッグでの
                // ホールドをしやすくする（2026-08-18追加）。背景の
                // `VideoProgressIndicator`（再生済み/バッファ済みの色分け、
                // `allowScrubbing: false`でジェスチャーを持たせない）に、
                // トラックを透明にした`Slider`を重ねてつまみとドラッグ
                // 操作だけを担わせる構成。両者はそれぞれ独自にトラック幅を
                // 計算するため水平方向のピクセル完全一致までは追求しない。
                child: SizedBox(
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: false,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 0,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          min: 0,
                          max: sliderMax,
                          value: sliderValue,
                          onChanged: durationMs <= 0
                              ? null
                              : (v) {
                                  setState(() => _dragPositionMs = v);
                                  _controller.seekTo(
                                    Duration(milliseconds: v.round()),
                                  );
                                },
                          onChangeEnd: (_) =>
                              setState(() => _dragPositionMs = null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                _formatDuration(value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Icon(Icons.error_outline, color: Colors.white, size: 48),
          );
        }
        // `AspectRatio`をそのまま`Center`直下に置くと、`Column`が
        // 主軸（縦）方向に無制限の高さを子へ渡すため、縦長（ポート
        // レート）動画で画面の高さを大きく超えるオーバーフローが
        // 発生した（2026-08-11発覚）。`Expanded`で明示的に高さを
        // 画面残り分に制限し、`AspectRatio`が幅・高さ両方の制約内で
        // 収まるサイズを計算できるようにする。
        //
        // タップ判定は`Expanded`領域全体（動画の周囲の黒い余白＝
        // レターボックス部分も含む）に対して行う（2026-08-14変更。以前は
        // `AspectRatio`の実サイズにだけ`GestureDetector`を付けていたため、
        // 動画の座標上でも余白部分をクリックすると反応しない不具合があった）。
        // 画像ページ（[_ImageViewerPage]）と異なり、動画本体のタップは
        // 「閉じる」ではなく常に再生/一時停止のトグルにするため、外側の
        // 「タップで閉じる」ジェスチャーは持たせない（閉じるのはEscキー・
        // 下スワイプ・AppBarの戻るボタンで行う。以前は動画全体を覆う
        // 「タップで閉じる」の`GestureDetector`とこのトグル用
        // `GestureDetector`が入れ子になっており、スワイプで動画ページへ
        // 遷移した直後は再生ボタンを押しても再生されない不具合があった。
        // 入れ子のジェスチャー判定自体を無くすことで解消した）。
        return Column(
          children: [
            Expanded(
              child: MouseRegion(
                onHover: (_) => _resetControlsVisibility(),
                // ダブルタップの左右判定に動画エリアの幅が要るため
                // `LayoutBuilder`で包む（2026-08-18追加）。
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _togglePlayback,
                      // モバイル以外では`onDoubleTapDown`自体を渡さない
                      // （`_isMobilePlatform`のdocコメント参照。常設すると
                      // 全プラットフォームでシングルタップの確定が
                      // ダブルタップ判定待ちの分だけ遅延してしまうため）。
                      onDoubleTapDown: _isMobilePlatform
                          ? (details) => _handleDoubleTapSkip(
                              details,
                              constraints.maxWidth,
                            )
                          : null,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              // Web（video_player_web）は<video>要素を直接
                              // DOMへ描画するプラットフォームビューのため、
                              // 動画のピクセル上のクリックがFlutterの
                              // ジェスチャー検出まで届かないことがある
                              // （2026-08-19判明。レターボックス部分は
                              // Flutterが直接描画しているため外側の
                              // GestureDetectorで問題無く反応するが、動画
                              // 本体は無反応だった）。動画と同じ範囲を覆う
                              // 透明なオーバーレイをVideoPlayerの直後
                              // （＝より手前）に重ね、タップ/ダブルタップを
                              // こちらで捕捉し直す。外側のGestureDetector
                              // （レターボックス部分用）は引き続き維持する。
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, videoConstraints) {
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _togglePlayback,
                                      onDoubleTapDown: _isMobilePlatform
                                          ? (details) => _handleDoubleTapSkip(
                                              details,
                                              videoConstraints.maxWidth,
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                              // 一時停止中は常時、再生中はポインター移動から
                              // 数秒間だけ、中央に再生/一時停止＋10秒送り/戻し
                              // ボタンを表示する（2026-08-14追加・2026-08-18に
                              // 10秒送り/戻し追加＋ポインター連動化）。個々の
                              // ボタンは実際にタップを受け取るため、外側の
                              // `onTap: _togglePlayback`（動画本体タップでの
                              // トグル）とは独立して共存する。
                              if (!_controller.value.isPlaying ||
                                  _controlsVisible)
                                _CenterControls(
                                  isPlaying: _controller.value.isPlaying,
                                  onTogglePlayback: _togglePlayback,
                                  onSkipBack: () {
                                    _skip(const Duration(seconds: -10));
                                    _resetControlsVisibility();
                                  },
                                  onSkipForward: () {
                                    _skip(const Duration(seconds: 10));
                                    _resetControlsVisibility();
                                  },
                                ),
                              // モバイルでのダブルタップ10秒送り/戻し操作の
                              // フィードバック（2026-08-18追加）。中央の
                              // `_CenterControls`と重ならないよう上寄せに
                              // 配置する。
                              if (_skipFlashLabel != null)
                                Align(
                                  alignment: const Alignment(0, -0.5),
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _skipFlashLabel!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildControlBar(),
          ],
        );
      },
    );
  }
}

/// 動画中央に表示する再生/一時停止＋10秒送り/戻しの3ボタン
/// （[_VideoViewerPage]参照、2026-08-14追加・2026-08-18に10秒送り/戻し
/// ボタンを追加）。各ボタンは[_CircleIconButton]で実際にタップを
/// 受け取るため、外側の`GestureDetector(onTap: _togglePlayback)`
/// （動画本体タップでのトグル）とは独立して動作する。
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.isPlaying,
    required this.onTogglePlayback,
    required this.onSkipBack,
    required this.onSkipForward,
  });

  final bool isPlaying;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleIconButton(
          icon: Icons.replay_10,
          size: 44,
          iconSize: 26,
          onTap: onSkipBack,
        ),
        const SizedBox(width: 20),
        _CircleIconButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: 64,
          iconSize: 40,
          onTap: onTogglePlayback,
        ),
        const SizedBox(width: 20),
        _CircleIconButton(
          icon: Icons.forward_10,
          size: 44,
          iconSize: 26,
          onTap: onSkipForward,
        ),
      ],
    );
  }
}

/// [_CenterControls]の3ボタンで共通に使う黒45%円・白アイコンの
/// タップ可能なボタン（2026-08-18追加）。
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

/// ファイル・動画添付メッセージの表示（[_MessageRow._attachmentContent]
/// 参照、2026-08-10改修）。以前はブロック全体のタップで即座に
/// `launchUrl`（ダウンロード相当）していたが、ポインターを乗せた時
/// （モバイルは常時）だけ右上にダウンロードボタンを出す方式に変更した。
/// Markdown（.md/.markdown）ファイルはさらに、本文をプレビュー表示できる
/// カードにする（初期状態は高さを制限した省略表示、シェブロンで全文表示に
/// 展開、右下に常時ダウンロードボタンを表示）。
class _FileAttachmentBlock extends StatefulWidget {
  const _FileAttachmentBlock({
    required this.metadata,
    required this.onBubbleColor,
    required this.isGekiga,
  });

  final MessageFileMetadata metadata;
  final Color onBubbleColor;
  final bool isGekiga;

  /// Markdownプレビューを提供する上限サイズ。これを超える場合は取得・
  /// レンダリングのコストを避け、通常のファイル行にフォールバックする。
  static const _maxPreviewBytes = 1024 * 1024;

  /// マークダウンカードの横幅上限。以前は340だったが、狭さゆえに全表示時
  /// 折り返しが増えて縦に長大化する不具合が報告された（2026-08-10）ため
  /// 拡大した。
  static const _markdownCardMaxWidth = 480.0;

  /// この添付がプレビュー可能なMarkdownファイルかどうか。`_MessageRow`が
  /// `_GekigaBubble`の枠を纏わせるかどうかの判定（`_FileAttachmentBlock`
  /// が自前の枠＝`GekigaJointedTileList`を持つため、外側の枠は二重表示に
  /// なる）にも使うため、`State`内の判定ロジックと共有できるようstaticに
  /// 切り出す（2026-08-10追加）。動画は`_attachmentContent`で別分岐に
  /// なり`_FileAttachmentBlock`自体に到達しなくなったため、`isVideo`引数は
  /// 2026-08-11に削除した。
  static bool isPreviewableMarkdown(MessageFileMetadata metadata) =>
      (metadata.extension == 'md' || metadata.extension == 'markdown') &&
      metadata.sizeBytes <= _maxPreviewBytes;

  @override
  State<_FileAttachmentBlock> createState() => _FileAttachmentBlockState();
}

class _FileAttachmentBlockState extends State<_FileAttachmentBlock>
    with AutomaticKeepAliveClientMixin {
  bool _hovering = false;
  bool _expanded = false;
  Future<String?>? _markdownFuture;

  /// URLをキーにしたMarkdown本文の取得結果キャッシュ（クラス全体で共有）。
  /// メッセージ一覧は`ScrollablePositionedList`（内部的にSliverList相当）だが、
  /// 画面外に出た`_FileAttachmentBlockState`は破棄され、再度画面内に
  /// 入ると`initState()`が再実行されて`http.get`が毎回走ってしまって
  /// いた（画像は`Image.network`のImageCacheで自動的にキャッシュされる
  /// ため、この問題が起きない）。`AutomaticKeepAliveClientMixin`（下記
  /// `wantKeepAlive`）で画面外でもStateごと保持されるようにするのが
  /// 主対応だが、同じファイルを参照する別インスタンスが現れた場合の保険
  /// として、取得結果自体もURLキーでキャッシュする（2026-08-12追加）。
  /// Markdownファイルの内容は不変前提のため、明示的な失効処理は設けない。
  static final Map<String, Future<String?>> _markdownCache = {};

  bool get _isMarkdown =>
      _FileAttachmentBlock.isPreviewableMarkdown(widget.metadata);

  @override
  bool get wantKeepAlive => _isMarkdown;

  /// ホバーの概念が無いモバイルでは、ダウンロードボタンを常時表示する
  /// （Web版もモバイルブラウザなら`defaultTargetPlatform`がこの判定になる）。
  bool get _alwaysShowDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_isMarkdown) {
      _markdownFuture = _markdownCache.putIfAbsent(
        widget.metadata.url,
        _fetchMarkdown,
      );
    }
  }

  Future<String?> _fetchMarkdown() async {
    try {
      final response = await http
          .get(Uri.parse(widget.metadata.url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      // `response.body`はContent-Typeのcharset宣言に依存し、未指定時は
      // latin1にフォールバックする。Firebase StorageのダウンロードURLは
      // .mdファイルにcharset=utf-8を明示しないため、日本語が文字化けする
      // （2026-08-10発覚）。常にUTF-8として復号する。
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _download() async {
    await launchUrl(
      Uri.parse(widget.metadata.url),
      mode: LaunchMode.externalApplication,
    );
  }

  /// クリップボードへコピーするのみで、確認UI（スナックバー等）は出さない
  /// （2026-08-12、ポップアップでの全表示撤回と合わせてユーザー指示により
  /// スナックバー表示を取りやめた）。
  Future<void> _copyMarkdown(String markdownText) async {
    await Clipboard.setData(ClipboardData(text: markdownText));
  }

  /// 拡大表示（140px⇔360px）の高さ変化量。
  static const _expandDelta = 220.0;

  /// メッセージ一覧が`reverse: true`のため、アイテムの高さが変わると既定
  /// では画面下端が起点になり上方向へ伸びる（Sliverの座標系上、各アイテムの
  /// 「配列上の開始位置＝画面下端」が固定され、高さが変わる分は「配列上の
  /// 終了位置＝画面上端」側だけが動くため）。上端を起点に下方向へ伸びるように
  /// 見せるため、高さが変わった直後に周囲のスクロール位置を変化量の分だけ
  /// 補正する（2026-08-12追加）。`Scrollable.maybeOf`でメッセージ一覧の
  /// 祖先Scrollableを、ウィジェット階層越しに配線せず取得する
  /// （2026-08-21、`ScrollablePositionedList`移行後も内部で通常の
  /// `Scrollable`を使うため同じ手法が使えるはずだが、内部的に2本のリストを
  /// 同期させる構造のため要動作確認）。
  void _toggleExpanded() {
    final delta = _expanded ? -_expandDelta : _expandDelta;
    setState(() => _expanded = !_expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) return;
      final position = scrollable.position;
      position.jumpTo(position.pixels + delta);
    });
  }

  /// ホバー/常時表示のダウンロードボタン。半透明の黒地＋白アイコンという
  /// 固定配色にすることで、乗っている吹き出し・カードの色（明るい/暗い
  /// どちらでも、フラット/劇画どちらでも）に関わらず視認できるようにする。
  /// [filled]をfalseにすると、この黒丸の背景無しでアイコンだけを描く
  /// （Markdownカードのfooterはカード自体が既に配色済みで、周りに紛れる
  /// 心配が無いため、コピーアイコンと揃えて丸背景無しにする、2026-08-12
  /// 追加）。
  Widget _downloadButton({
    required bool small,
    bool filled = true,
    Color color = Colors.white,
  }) {
    final icon = Icon(Icons.download, size: small ? 16 : 18, color: color);
    if (!filled) {
      return InkWell(
        onTap: _download,
        child: Padding(padding: EdgeInsets.all(small ? 6 : 8), child: icon),
      );
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _download,
        child: Padding(padding: EdgeInsets.all(small ? 6 : 8), child: icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isMarkdown) return _buildPlainRow();

    return FutureBuilder<String?>(
      future: _markdownFuture,
      builder: (context, snapshot) {
        final content = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            content == null) {
          // 取得中・取得失敗時は通常のファイル行にフォールバックする。
          return _buildPlainRow();
        }
        return _buildMarkdownCard(context, content);
      },
    );
  }

  Widget _buildPlainRow() {
    final showIcon = _hovering || _alwaysShowDownload;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  color: widget.onBubbleColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.metadata.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: widget.onBubbleColor),
                      ),
                      Text(
                        _MessageRow._formatFileSize(widget.metadata.sizeBytes),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.onBubbleColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showIcon)
            Positioned(top: -6, right: -6, child: _downloadButton(small: true)),
        ],
      ),
    );
  }

  Widget _buildMarkdownCard(BuildContext context, String markdownText) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = widget.isGekiga ? GekigaColors.onPanel : colorScheme.onSurface;
    final subFg = widget.isGekiga
        ? GekigaColors.onPanel.withValues(alpha: 0.75)
        : colorScheme.onSurfaceVariant;

    // `ThemeData.dark()`を単体で生成すると`textTheme.bodyMedium?.fontSize`が
    // 未解決（null）のままになり`MarkdownStyleSheet.fromTheme`のassertに
    // 失敗する（2026-08-10発覚）。`MaterialApp`を経由しないと`Typography`が
    // 完全には適用されないため。実際に画面へ描画されているアプリ本体の
    // `Theme.of(context)`は必ずフォントサイズ込みで解決済みなので、これを
    // ベースにして劇画UI用の文字色だけ上書きする。
    final baseStyleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context));
    final markdownStyleSheet = widget.isGekiga
        ? baseStyleSheet.copyWith(
            a: baseStyleSheet.a?.copyWith(color: GekigaColors.onPanel),
            p: baseStyleSheet.p?.copyWith(color: GekigaColors.onPanel),
            code: baseStyleSheet.code?.copyWith(
              color: GekigaColors.onPanel,
              backgroundColor: Colors.black.withValues(alpha: 0.35),
            ),
            h1: baseStyleSheet.h1?.copyWith(color: GekigaColors.onPanel),
            h2: baseStyleSheet.h2?.copyWith(color: GekigaColors.onPanel),
            h3: baseStyleSheet.h3?.copyWith(color: GekigaColors.onPanel),
            h4: baseStyleSheet.h4?.copyWith(color: GekigaColors.onPanel),
            h5: baseStyleSheet.h5?.copyWith(color: GekigaColors.onPanel),
            h6: baseStyleSheet.h6?.copyWith(color: GekigaColors.onPanel),
            em: baseStyleSheet.em?.copyWith(color: GekigaColors.onPanel),
            strong: baseStyleSheet.strong?.copyWith(
              color: GekigaColors.onPanel,
            ),
            del: baseStyleSheet.del?.copyWith(color: GekigaColors.onPanel),
            blockquote: baseStyleSheet.blockquote?.copyWith(
              color: GekigaColors.onPanel.withValues(alpha: 0.85),
            ),
            listBullet: baseStyleSheet.listBullet?.copyWith(
              color: GekigaColors.onPanel,
            ),
            tableHead: baseStyleSheet.tableHead?.copyWith(
              color: GekigaColors.onPanel,
            ),
            tableBody: baseStyleSheet.tableBody?.copyWith(
              color: GekigaColors.onPanel,
            ),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: GekigaColors.onPanel.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        : baseStyleSheet;

    final markdownBody = MarkdownBody(
      data: markdownText,
      styleSheet: markdownStyleSheet,
    );

    // Markdown本文を文字数で機械的に切ると表・リスト等の構文が壊れる恐れが
    // あるため、常にフルレンダリングした上で表示領域の高さだけを制限する。
    // 表（`Table`+`FlexColumnWidth`）はスクロール前提の縮小表示に対応して
    // おらず、単純な`ConstrainedBox(maxHeight)`で高さを強制すると制約違反で
    // 描画が壊れる（2026-08-10発覚・修正）ため、`SizedBox`で確定高さの窓を
    // 作り、その中に`SingleChildScrollView`で本来の自然な高さのまま描画
    // させてクリップする、という標準的な構成にする。
    //
    // 全表示は一度ポップアップ（`showDialog`）で試したが、メッセージ画面の
    // ままで拡大表示してほしいとの指摘を受け撤回した（2026-08-12）。以前の
    // 「その場で無制限に縦へ伸びる」実装ではスクロールできず読みにくかった
    // ため、代わりに固定高さ（360px）へ拡大した上でスクロール可能にする
    // （折り畳み時は140pxでスクロール無効のまま）。
    final body = GestureDetector(
      onTap: _toggleExpanded,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: SizedBox(
          height: _expanded ? 360 : 140,
          child: SingleChildScrollView(
            physics: _expanded
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: markdownBody,
          ),
        ),
      ),
    );

    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 16,
                color: subFg,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.description_outlined, size: 16, color: subFg),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.metadata.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                Text(
                  _MessageRow._formatFileSize(widget.metadata.sizeBytes),
                  style: TextStyle(fontSize: 10, color: subFg),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _copyMarkdown(markdownText),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.copy_outlined, size: 16, color: subFg),
            ),
          ),
          const SizedBox(width: 4),
          _downloadButton(small: false, filled: false, color: subFg),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [body, footer],
    );

    if (widget.isGekiga) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _FileAttachmentBlock._markdownCardMaxWidth,
        ),
        child: GekigaJointedTileList(
          seeds: [widget.metadata.url.hashCode],
          selectedFlags: const [false],
          children: [content],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
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
    this.skipFrame = false,
  });

  final Widget child;
  final int seed;
  final bool isMe;

  /// 右寄せ表示（自分・sideBySideレイアウト）かどうか。真なら吹き出しの
  /// 形状（平行四辺形の傾き）を左右反転する（2026-08-06追加）。
  final bool alignRight;

  /// 中身が既に自前の枠を持つコンテンツ（添付画像・動画プレビュー・
  /// マークダウンプレビューカード）かどうか（2026-08-10追加、2026-08-11に
  /// 動画も対象に追加）。画像は当初、傾き（skew）だけを0にして対応していた
  /// が、`distortedParallelogramVertices`は傾きとは別に四隅を`seed`で
  /// ランダムにジッターさせており（[MonochromeBoxPainter]の内側リングの
  /// inset量とズレうる）、`ClipRRect`の直線的な写真との不整合で黒い隙間が
  /// 縁からはみ出す不具合が再発した。動画プレビュー・マークダウンプレビュー
  /// カード（`_FileAttachmentBlock`）は`_GekigaPhotoMat`/`GekigaJointedTileList`
  /// という自前の枠を既に持っており、外側にもこの吹き出し枠を重ねると
  /// 二重表示になる。いずれも数値調整で追いかけず、モノクロボックス装飾
  /// （[CustomPaint]自体）を纏わせないことで根本的に解消する（テキスト
  /// メッセージの見た目は変えない）。
  final bool skipFrame;

  @override
  Widget build(BuildContext context) {
    if (skipFrame) {
      return child;
    }
    return CustomPaint(
      painter: _GekigaBubblePainter(
        seed: seed,
        isMe: isMe,
        alignRight: alignRight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
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
    // URLのような空白を含まない長い1行のテキストは折り返されず、吹き出しの
    // 幅がテキスト幅に応じて際限なく広がりうる（吹き出し自体に上限幅の
    // 制約は無い）。傾き量を「幅の10%」のままにすると、幅が広い吹き出しほど
    // 傾きがpadding（28px）を上回りテキストが縁からはみ出すため、絶対量を
    // 20pxで頭打ちにする（2026-08-10追加）。
    final vertices = distortedParallelogramVertices(
      size.width,
      size.height,
      seed,
      skewOverride: math.min(size.width * 0.10, 20),
    );
    MonochromeBoxPainter(
      vertices: alignRight ? mirrorHorizontal(vertices, size.width) : vertices,
      thicknessBase: _kGekigaBoxBorderThickness,
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
    // 入力欄は横幅に対して縦が極端に短い箱になりやすく、既定の「横幅の
    // 10%」の傾きをそのまま使うと文字にかかってしまう。縦幅基準の控えめな
    // 傾きにする（2026-08-10、`_GekigaComposerField`のpaddingと合わせて
    // 文字がはみ出さない程度に調整）。ただしこの値をそのまま使うと複数行
    // 入力で箱が縦に伸びるほど傾きが際限なく大きくなり、外側のPadding
    // （水平20px）を超えて文字・ペタピタアイコンが平行四辺形の外に
    // はみ出してしまうため、16.0（水平Paddingを下回る安全な値）で
    // 頭打ちにする（2026-08-11修正）。
    final vertices = mirrorHorizontal(
      distortedParallelogramVertices(
        size.width,
        size.height,
        seed,
        skewOverride: math.min(size.height * 0.12, 16.0),
      ),
      size.width,
    );
    MonochromeBoxPainter(
      vertices: vertices,
      thicknessBase: _kGekigaBoxBorderThickness,
      fillColor: Colors.white,
      seed: seed,
      invert: true,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GekigaComposerFieldPainter oldDelegate) =>
      false;
}
