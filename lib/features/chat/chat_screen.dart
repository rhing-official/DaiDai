import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../theme/app_theme_extras.dart';

/// 一対・広場（お部屋）どちらの会話でも使える汎用チャット画面。
/// メッセージの取得・送信方法は呼び出し元がstream/callbackとして渡す。
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.title,
    required this.currentUserId,
    required this.messagesStream,
    required this.onSend,
    this.showSenderAvatar = false,
    this.onCallPressed,
    super.key,
  });

  final String title;
  final String currentUserId;
  final Stream<List<Message>> messagesStream;
  final Future<void> Function(String content) onSend;

  /// 広場（複数人の会話）では相手ごとに送信者を見分けやすいよう、
  /// メッセージにRhing IDのイニシャルアイコンを表示する。一対では表示しない。
  final bool showSenderAvatar;

  /// 音声通話の発信ボタン。一対（1対1）のみで渡す（フェーズ1は広場の通話は未対応）。
  final VoidCallback? onCallPressed;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();

  Future<void> _send() async {
    final content = _textController.text.trim();
    if (content.isEmpty) return;
    _textController.clear();
    await widget.onSend(content);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final floatingShadow =
        Theme.of(context).extension<AppThemeExtras>()?.floatingShadow ??
            AppThemeExtras.none;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(widget.title),
        actions: [
          if (widget.onCallPressed != null)
            IconButton(
              icon: const Icon(Icons.call_outlined),
              onPressed: widget.onCallPressed,
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
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == widget.currentUserId;
                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: floatingShadow,
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: isMe
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );

                    if (!widget.showSenderAvatar || isMe) {
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: bubble,
                      );
                    }

                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _SenderAvatar(rhingId: message.senderRhingId),
                          const SizedBox(width: 8),
                          Flexible(child: bubble),
                        ],
                      ),
                    );
                  },
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
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: colorScheme.primary),
                    onPressed: _send,
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

/// 送信者のRhing IDから生成する、写真未設定時のイニシャルアイコン。
/// 蔵（プロフィール画像）機能が実装されるまでの暫定表示。
class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.rhingId});

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
  Widget build(BuildContext context) {
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
