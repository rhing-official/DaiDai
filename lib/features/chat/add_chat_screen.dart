import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import 'chat_screen.dart';

/// 相手のRhing IDを入力して一対（1対1チャット）を開始する画面。
/// 仲間承認制などのスパム対策はフェーズ1の後続タスクで追加する。
class AddChatScreen extends ConsumerStatefulWidget {
  const AddChatScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<AddChatScreen> createState() => _AddChatScreenState();
}

class _AddChatScreenState extends ConsumerState<AddChatScreen> {
  final _controller = TextEditingController();
  bool _isSearching = false;
  String? _errorMessage;

  Future<void> _startChat() async {
    final rhingId =
        _controller.text.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
    if (rhingId.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final userRepository = ref.read(userRepositoryProvider);
      final other = await userRepository.findByRhingId(rhingId);
      if (other == null) {
        setState(() {
          _errorMessage = 'そのRhing IDの住人は見つかりませんでした';
        });
        return;
      }
      if (other.userId == widget.currentUser.userId) {
        setState(() {
          _errorMessage = '自分自身とは一対を開始できません';
        });
        return;
      }

      final dmRepository = ref.read(directMessageRepositoryProvider);
      final dm = await dmRepository.getOrCreateDirectMessage(
        widget.currentUser,
        other,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            title: '@${other.rhingId}',
            currentUserId: widget.currentUser.userId,
            messagesStream: dmRepository.watchMessages(dm.dmId),
            onSend: (content) => dmRepository.sendTextMessage(
              dmId: dm.dmId,
              senderId: widget.currentUser.userId,
              content: content,
            ),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'エラーが発生しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('相手を追加')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('相手のRhing IDを入力して一対を開始します。'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '相手のRhing ID',
                prefixText: '@',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _startChat(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSearching ? null : _startChat,
              child: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('一対を開始'),
            ),
          ],
        ),
      ),
    );
  }
}
