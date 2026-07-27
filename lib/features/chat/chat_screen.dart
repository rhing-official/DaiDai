import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/strings.dart';
import '../../models/chat_layout_style.dart';
import '../../models/message.dart';
import '../../models/send_key_mode.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../theme/app_theme_extras.dart';
import '../../utils/link_detection.dart';
import '../../utils/message_time.dart';
import '../../widgets/link_preview_card.dart';
import '../../widgets/linkified_text.dart';

/// 一対・広場（お部屋）どちらの会話でも使える汎用チャット画面。
/// メッセージの取得・送信方法は呼び出し元がstream/callbackとして渡す。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.title,
    required this.currentUserId,
    required this.isDm,
    required this.messagesStream,
    required this.onSend,
    this.onCallPressed,
    this.onVideoCallPressed,
    this.extraActions,
    this.readReceiptsEnabled = true,
    this.onMarkRead,
    this.banner,
    this.onSenderTap,
    this.onHideMessages,
    this.onEditMessage,
    this.onUnsendMessage,
    this.onSetReaction,
    super.key,
  });

  final String title;
  final String currentUserId;

  /// 一対（1対1）か広場（グループ）か。[ChatLayoutStyle.sideBySide]で、
  /// 相手のアイコン・呼び名を表示するかどうかの判定に使う。
  final bool isDm;

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

  /// 選択したメッセージを自分のアカウントから見えなくする（範囲選択削除）。
  /// nullなら選択モード自体を提供しない。
  final Future<void> Function(List<String> messageIds)? onHideMessages;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  late bool _hasHardwareKeyboard;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final locale = ref.watch(appLocaleProvider);
    final layoutStyle = ref.watch(chatLayoutStyleProvider);
    final strings = ref.watch(appStringsProvider);
    final floatingShadow =
        Theme.of(context).extension<AppThemeExtras>()?.floatingShadow ??
            AppThemeExtras.none;

    return Scaffold(
      appBar: AppBar(
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

                // 返信元メッセージの引用プレビューに使う。現在ロード済みの
                // （最新50件の）範囲に返信元があれば、こちらを優先して
                // 表示する（編集済みなら最新の内容を反映できる）。範囲外
                // ならMessage側の非正規化フィールド（replyToSnippet等）に
                // フォールバックする（_MessageRow参照）。
                final messagesById = {
                  for (final m in messages) m.messageId: m,
                };

                // messagesは新しい順（index 0が最新）。日付区切りを「その日の
                // 最初のメッセージの直上」に挿入したいので、一旦古い順に走査して
                // 区切り込みのリストを組み立ててから反転する。reverse:trueの
                // ListViewにそのまま渡すと、index 0（リストの末尾＝一番新しい
                // 要素）が画面下端に来て、見た目は上から古い順（区切り→その日の
                // メッセージ…）に正しく並ぶ。
                final entries = <Widget>[];
                DateTime? currentDay;
                for (var i = messages.length - 1; i >= 0; i--) {
                  final message = messages[i];
                  final sentAt = message.sentAt?.toDate();
                  if (sentAt != null &&
                      (currentDay == null || !isSameDay(sentAt, currentDay))) {
                    currentDay = sentAt;
                    entries.add(_DateSeparator(date: sentAt, locale: locale));
                  }
                  entries.add(
                    _MessageRow(
                      message: message,
                      isMe: message.senderId == widget.currentUserId,
                      currentUserId: widget.currentUserId,
                      timeLabel: sentAt != null
                          ? formatMessageTime(sentAt, timeFormat)
                          : null,
                      colorScheme: colorScheme,
                      floatingShadow: floatingShadow,
                      readReceiptsEnabled: widget.readReceiptsEnabled,
                      layoutStyle: layoutStyle,
                      isDm: widget.isDm,
                      onSenderTap: _selecting ? null : widget.onSenderTap,
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
                    ),
                  );
                }
                final reversedEntries = entries.reversed.toList();

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: reversedEntries.length,
                  itemBuilder: (context, index) => reversedEntries[index],
                );
              },
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
    required this.readReceiptsEnabled,
    required this.layoutStyle,
    required this.isDm,
    this.onSenderTap,
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
  });

  final Message message;
  final bool isMe;
  final String currentUserId;
  final String? timeLabel;
  final ColorScheme colorScheme;
  final List<BoxShadow> floatingShadow;
  final bool readReceiptsEnabled;
  final ChatLayoutStyle layoutStyle;
  final bool isDm;
  final void Function(String userId)? onSenderTap;

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
                                  _SenderAvatar(userId: reader.userId, rhingId: null),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SenderName(
                                      userId: reader.userId,
                                      rhingId: null,
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

    final onBubbleColor = isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

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
              _SenderName(userId: replySenderId, rhingId: replySenderRhingId),
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

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: floatingShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?replyPreview,
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: LinkifiedText(
                  message.content,
                  style: TextStyle(color: onBubbleColor),
                  linkColor: isMe ? colorScheme.onPrimary : colorScheme.primary,
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
      ),
    );

    // 吹き出しの角に既読チェックマークを重ねる。バブルが右寄せの時は左下、
    // 左寄せの時は右下（吹き出しの中心寄り＝アイコンと反対側）に表示する
    // （isMeではなくalignRightで決める。allLeftスタイルでは自分のメッセージも
    // 左寄せになるため、isMeだけで判定すると常にアイコン側に重なってしまう）。
    // 吹き出しの内容（特に画像だけの小さい吹き出し）に重ならないよう、
    // 角からしっかり離す。
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

    final bubbleWithReadMark = Stack(
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
      );
      final senderName = _SenderName(
        userId: message.senderId,
        rhingId: message.senderRhingId,
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

    // テキストメッセージの自分の投稿のみ編集可能（画像等contentType='text'
    // 以外は将来実装時もまず本文編集の対象外という方針、Planでの検討通り）。
    final canEdit = isMe && message.contentType == 'text' && onEdit != null;

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
        canSelect: canSelect,
        strings: strings,
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
        child: content,
      );
    }

    if (message.reactions.isEmpty) return body;
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [body, _reactionBar(alignRight)],
    );
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

/// メッセージ1件に対する長押し/右クリックのコンテキストメニューと、
/// 左スワイプ（軽く=返信、最後まで=編集。編集は[canEdit]がtrueの時のみ）を
/// まとめて扱う。選択モード中（[ChatScreen]の範囲選択削除）は使わない
/// （_MessageRow.build参照）。
class _MessageInteractions extends StatefulWidget {
  const _MessageInteractions({
    required this.child,
    required this.canEdit,
    required this.canSelect,
    required this.strings,
    required this.onReply,
    this.onEdit,
    this.onUnsend,
    this.onReact,
    this.onSelect,
  });

  final Widget child;
  final bool canEdit;
  final bool canSelect;
  final Strings strings;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onUnsend;
  final void Function(String emoji)? onReact;
  final VoidCallback? onSelect;

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

  RelativeRect _menuPosition(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _openMenu(Offset globalPosition) async {
    final strings = widget.strings;
    final action = await showMenu<_MessageMenuAction>(
      context: context,
      position: _menuPosition(globalPosition),
      items: [
        PopupMenuItem(
          value: _MessageMenuAction.reply,
          child: Text(strings.chatReplyAction),
        ),
        if (widget.onReact != null)
          PopupMenuItem(
            value: _MessageMenuAction.react,
            child: Text(strings.chatReactAction),
          ),
        if (widget.onEdit != null)
          PopupMenuItem(
            value: _MessageMenuAction.edit,
            child: Text(strings.chatEditAction),
          ),
        if (widget.onUnsend != null)
          PopupMenuItem(
            value: _MessageMenuAction.unsend,
            child: Text(strings.chatUnsendAction),
          ),
        if (widget.canSelect)
          PopupMenuItem(
            value: _MessageMenuAction.select,
            child: Text(strings.chatSelectAction),
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _MessageMenuAction.reply:
        widget.onReply();
      case _MessageMenuAction.edit:
        widget.onEdit?.call();
      case _MessageMenuAction.unsend:
        widget.onUnsend?.call();
      case _MessageMenuAction.react:
        await _openReactionPicker(globalPosition);
      case _MessageMenuAction.select:
        widget.onSelect?.call();
      case null:
        break;
    }
  }

  Future<void> _openReactionPicker(Offset globalPosition) async {
    final emoji = await showMenu<String>(
      context: context,
      position: _menuPosition(globalPosition),
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
    if (emoji != null) widget.onReact?.call(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _openMenu(details.globalPosition),
      onSecondaryTapDown: (details) => _openMenu(details.globalPosition),
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
  const _SenderName({required this.userId, required this.rhingId});

  final String userId;
  final String? rhingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname =
        ref.watch(watchedUserProvider(userId)).value?.effectiveNickname?.text;
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
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 送信者のアイコン。蔵で設定した実際のアイコン（[AppUser.effectiveIcon]）が
/// あればそれを表示し、未設定ならRhing IDから生成する色分けイニシャルに
/// フォールバックする。
class _SenderAvatar extends ConsumerWidget {
  const _SenderAvatar({required this.userId, required this.rhingId});

  final String userId;
  final String? rhingId;

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
    final iconUrl =
        ref.watch(watchedUserProvider(userId)).value?.effectiveIcon?.url;
    if (iconUrl != null) {
      return CircleAvatar(radius: 16, backgroundImage: NetworkImage(iconUrl));
    }
    final id = rhingId ?? '?';
    final color = _palette[id.hashCode.abs() % _palette.length];
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
