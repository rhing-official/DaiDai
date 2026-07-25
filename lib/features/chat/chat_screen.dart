import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message.dart';
import '../../models/send_key_mode.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/send_key_mode_provider.dart';
import '../../providers/user_providers.dart';
import '../../theme/app_theme_extras.dart';
import '../../utils/message_time.dart';

/// 一対・広場（お部屋）どちらの会話でも使える汎用チャット画面。
/// メッセージの取得・送信方法は呼び出し元がstream/callbackとして渡す。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.title,
    required this.currentUserId,
    required this.messagesStream,
    required this.onSend,
    this.onCallPressed,
    this.onVideoCallPressed,
    this.extraActions,
    super.key,
  });

  final String title;
  final String currentUserId;
  final Stream<List<Message>> messagesStream;
  final Future<void> Function(String content, {bool silent}) onSend;

  /// 音声通話の発信ボタン。一対（1対1）のみで渡す（グループ通話は未対応）。
  final VoidCallback? onCallPressed;

  /// ビデオ通話の発信ボタン。一対（1対1）のみで渡す（グループ通話は未対応）。
  final VoidCallback? onVideoCallPressed;

  /// 呼び出し側固有のAppBarアクション（例: 広場の詳細を開くボタン）。
  final List<Widget>? extraActions;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();

  Future<void> _send({bool silent = false}) async {
    final content = _textController.text.trim();
    if (content.isEmpty) return;
    _textController.clear();
    await widget.onSend(content, silent: silent);
  }

  /// メッセージ入力欄でのEnterキー処理。設定（[SendKeyMode]）に応じて、
  /// 送信・相手に通知しない送信・改行のどれを行うかを自前で判定する。
  /// TextFieldの既定のEnter処理（ハードウェアキーボードからの生キーイベントに
  /// 対しては、プラットフォームのIME経由の改行挿入が常に走るとは限らない）に
  /// 依存すると環境によって改行が入らないことがあったため、改行も自前で挿入する。
  ///
  /// キー割り当て:
  /// - Enterで送信モード: Enter=送信 / Shift+Enter=改行 / Ctrl+Enter=通知せず送信
  /// - Ctrl+Enterで送信モード: Enter=改行 / Ctrl+Enter=送信 / Ctrl+Shift+Enter=通知せず送信
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
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
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final floatingShadow =
        Theme.of(context).extension<AppThemeExtras>()?.floatingShadow ??
            AppThemeExtras.none;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(widget.title),
        actions: [
          ...?widget.extraActions,
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
        ],
      ),
      body: Column(
        children: [
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
                    entries.add(_DateSeparator(date: sentAt));
                  }
                  entries.add(
                    _MessageRow(
                      message: message,
                      isMe: message.senderId == widget.currentUserId,
                      timeLabel: sentAt != null
                          ? formatMessageTime(sentAt, timeFormat)
                          : null,
                      colorScheme: colorScheme,
                      floatingShadow: floatingShadow,
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
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
                        decoration: const InputDecoration(
                          hintText: 'メッセージを入力',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  Material(
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

/// メッセージ一覧の日付区切り。その日最初のメッセージの直上に、画面中央の
/// 丸みを帯びたラベルとして表示する。LINE等の「今日」「昨日」のような相対
/// 表記ではなく、常に絶対日付（yyyy/mm/dd）で表す。
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

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
            formatMessageDate(date),
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

/// メッセージ1件分の表示。自分のメッセージは吹き出しのみ（時刻は吹き出しの下）、
/// 相手のメッセージはアイコン＋（呼び名・時刻の見出し行）を吹き出しの上に出し、
/// 見出し行の下へ吹き出しが展開する構成にする（一対・広場どちらも同じ見た目）。
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.isMe,
    required this.timeLabel,
    required this.colorScheme,
    required this.floatingShadow,
  });

  final Message message;
  final bool isMe;
  final String? timeLabel;
  final ColorScheme colorScheme;
  final List<BoxShadow> floatingShadow;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: floatingShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              message.content,
              style: TextStyle(
                color: isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (message.silent) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.notifications_off,
              size: 14,
              color: (isMe ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)
                  .withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (isMe) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bubble,
              if (timeLabel != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    timeLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SenderAvatar(userId: message.senderId, rhingId: message.senderRhingId),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: _SenderName(
                          userId: message.senderId,
                          rhingId: message.senderRhingId,
                        ),
                      ),
                      if (timeLabel != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          timeLabel!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  bubble,
                ],
              ),
            ),
          ],
        ),
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
