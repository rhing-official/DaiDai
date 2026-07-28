import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';

/// 友達申請の送信画面。相手のRhing IDを検索し、まだ友達でなければ申請を送る。
/// 既に友達の場合はそのまま一対を開く（＝IDを使うのは最初の1回だけで、
/// 以降はニックネームで見分けられるようにする方針）。
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
  String? _successMessage;

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    final rhingId =
        _controller.text.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
    if (rhingId.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final userRepository = ref.read(userRepositoryProvider);
      final other = await userRepository.findByRhingId(rhingId);
      if (other == null) {
        setState(() => _errorMessage = strings.friendSearchNotFound);
        return;
      }
      if (other.userId == widget.currentUser.userId) {
        setState(() => _errorMessage = strings.friendSearchSelf);
        return;
      }

      final friendRepository = ref.read(friendRepositoryProvider);
      final alreadyFriends = await friendRepository.isFriend(
        userId: widget.currentUser.userId,
        otherUserId: other.userId,
      );

      if (alreadyFriends) {
        final dmRepository = ref.read(directMessageRepositoryProvider);
        final dm = await dmRepository.getOrCreateDirectMessage(
          widget.currentUser,
          other,
        );
        if (!mounted) return;
        ref.read(goRouterProvider).pushReplacement(
          '/chat/dm',
          extra: DmChatArgs(
            currentUser: widget.currentUser,
            dm: dm,
            roomId: dm.defaultRoomId,
            // 作成直後の一対は常に「メイン」という名前の寄合が1つだけ
            // 存在する（DirectMessageRepository.getOrCreateDirectMessage/
            // FriendRepository.respond参照）。
            roomName: 'メイン',
          ),
        );
        return;
      }

      await friendRepository.sendRequest(from: widget.currentUser, to: other);
      if (!mounted) return;
      setState(() => _successMessage = strings.friendRequestSent);
      _controller.clear();
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
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
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(strings.friendSearchTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.friendSearchHint),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.friendSearchLabel,
                prefixText: '@',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _successMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSearching ? null : _submit,
              child: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.friendSearchButton),
            ),
          ],
        ),
      ),
    );
  }
}
