import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import 'chat_screen.dart';

/// 広場（グループ）作成画面。3人以上（自分＋2人以上）で作成する。
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _rhingIdController = TextEditingController();
  final _members = <AppUser>[];

  bool _isAddingMember = false;
  bool _isCreating = false;
  String? _errorMessage;

  Future<void> _addMember() async {
    final rhingId = _rhingIdController.text.trim().toLowerCase();
    if (rhingId.isEmpty) return;

    setState(() {
      _isAddingMember = true;
      _errorMessage = null;
    });

    try {
      final userRepository = ref.read(userRepositoryProvider);
      final user = await userRepository.findByRhingId(rhingId);
      if (user == null) {
        setState(() => _errorMessage = 'そのRhing IDの住人は見つかりませんでした');
        return;
      }
      if (user.userId == widget.currentUser.userId) {
        setState(() => _errorMessage = '自分自身は追加できません（自動的にメンバーになります）');
        return;
      }
      if (_members.any((m) => m.userId == user.userId)) {
        setState(() => _errorMessage = 'すでに追加済みです');
        return;
      }
      setState(() {
        _members.add(user);
        _rhingIdController.clear();
      });
    } finally {
      if (mounted) {
        setState(() => _isAddingMember = false);
      }
    }
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            title: group.name,
            currentUserId: widget.currentUser.userId,
            messagesStream: groupRepository.watchRoomMessages(
              group.groupId,
              group.defaultRoomId,
            ),
            onSend: (content) => groupRepository.sendRoomMessage(
              groupId: group.groupId,
              roomId: group.defaultRoomId,
              senderId: widget.currentUser.userId,
              content: content,
            ),
          ),
        ),
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
    _rhingIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('広場を作る')),
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
            const Text('メンバーをRhing IDで追加（自分＋2人以上が必要）'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rhingIdController,
                    decoration: const InputDecoration(
                      labelText: '相手のRhing ID',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addMember(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isAddingMember ? null : _addMember,
                  icon: const Icon(Icons.add),
                ),
              ],
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
                Chip(label: Text('@${widget.currentUser.rhingId}（自分）')),
                for (final member in _members)
                  Chip(
                    label: Text('@${member.rhingId}'),
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
