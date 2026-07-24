import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';

/// 友達一覧をプルダウン選択できるよう、Rhing IDではなく呼び名（未設定ならRhing ID）で表示する。
String _displayName(AppUser user) {
  final nickname = user.activeNickname?.text;
  return (nickname != null && nickname.isNotEmpty) ? nickname : '@${user.rhingId}';
}

/// 友達一覧（フルプロフィール、呼び名表示のため）を監視する。
final _candidateFriendsProvider =
    StreamProvider.family<List<AppUser>, String>((ref, userId) {
  final friendRepository = ref.watch(friendRepositoryProvider);
  final userRepository = ref.watch(userRepositoryProvider);
  return friendRepository.watchFriends(userId).asyncMap(
        (friends) => userRepository.getUsersByIds(
          friends.map((f) => f.friendUserId).toList(),
        ),
      );
});

/// 広場（グループ）作成画面。3人以上（自分＋2人以上）で作成する。
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _members = <AppUser>[];

  TextEditingController? _friendFieldController;
  bool _isCreating = false;
  String? _errorMessage;

  void _addMember(AppUser user) {
    setState(() {
      _members.add(user);
      _errorMessage = null;
    });
    _friendFieldController?.clear();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = '広場の名前を入力してください');
      return;
    }
    if (_members.length < 2) {
      setState(() => _errorMessage = '広場は3人以上（自分含む）で作成できます。あと${2 - _members.length}人追加してください');
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final groupRepository = ref.read(groupRepositoryProvider);
      final group = await groupRepository.createGroup(
        name: name,
        owner: widget.currentUser,
        members: _members,
      );

      if (!mounted) return;
      ref.read(goRouterProvider).pushReplacement(
        '/chat/group',
        extra: GroupChatArgs(currentUser: widget.currentUser, group: group),
      );
    } catch (e) {
      setState(() => _errorMessage = 'エラーが発生しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('広場を作る'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '広場の名前',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('メンバーを友達から追加（自分＋2人以上が必要）'),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final friendsAsync = ref.watch(
                  _candidateFriendsProvider(widget.currentUser.userId),
                );
                return friendsAsync.when(
                  data: (friends) {
                    if (friends.isEmpty) {
                      return const Text(
                        '友達がいません。先に縁結びで友達を追加してください',
                        style: TextStyle(color: Colors.grey),
                      );
                    }
                    final available = friends
                        .where((f) =>
                            !_members.any((m) => m.userId == f.userId))
                        .toList();
                    return Autocomplete<AppUser>(
                      displayStringForOption: _displayName,
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return available;
                        return available.where((u) =>
                            _displayName(u).toLowerCase().contains(query) ||
                            u.rhingId.toLowerCase().contains(query));
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        _friendFieldController = controller;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: '友達を選んで追加',
                            prefixIcon: Icon(Icons.person_add_alt),
                            border: OutlineInputBorder(),
                          ),
                        );
                      },
                      onSelected: _addMember,
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    '友達一覧の取得に失敗しました: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${_displayName(widget.currentUser)}（自分）')),
                for (final member in _members)
                  Chip(
                    label: Text(_displayName(member)),
                    onDeleted: () => setState(() => _members.remove(member)),
                  ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('作成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
