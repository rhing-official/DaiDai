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

/// 広場（グループ）作成ポップアップ（2026-07-29、画面遷移からポップアップ化）。
/// 3人以上（自分＋2人以上）で作成する。「＋」ボタンのメニューポップアップの
/// 上に重ねて表示される（`TalksTab._showAddMenu`参照）。
class CreateGroupDialogContent extends ConsumerStatefulWidget {
  const CreateGroupDialogContent({
    required this.currentUser,
    required this.onClose,
    required this.onCompleted,
    super.key,
  });

  final AppUser currentUser;

  /// 閉じる（×）ボタン。このポップアップ自体だけを閉じ、下に重なっている
  /// 「＋」メニューポップアップは開いたままにする。
  final VoidCallback onClose;

  /// 広場を開いて画面遷移する直前に呼ぶ。このポップアップ・その下に重なって
  /// いる「＋」メニューポップアップの両方を閉じる必要があるため、[onClose]
  /// とは別のコールバックとして分離している。
  final VoidCallback onCompleted;

  @override
  ConsumerState<CreateGroupDialogContent> createState() =>
      _CreateGroupDialogContentState();
}

class _CreateGroupDialogContentState
    extends ConsumerState<CreateGroupDialogContent> {
  final _nameController = TextEditingController();
  final _members = <AppUser>[];

  TextEditingController? _friendFieldController;
  bool _isCreating = false;
  String? _errorMessage;

  /// 寄合を複数扱うか（2026-07-29追加）。falseを選んだ場合、後から
  /// ハンバーガーメニューの「寄合を複数扱う」でtrueに切り替えられる
  /// （逆方向は不可、`Group.roomsEnabled`参照）。
  bool _roomsEnabled = true;

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
        roomsEnabled: _roomsEnabled,
      );

      if (!mounted) return;
      widget.onCompleted();
      ref.read(goRouterProvider).push(
        '/chat/group',
        extra: GroupChatArgs(
          currentUser: widget.currentUser,
          group: group,
          roomId: group.defaultRoomId,
          // 作成直後の広場は常に「メイン」という名前の寄合が1つだけ
          // 存在する（GroupRepository.createGroup参照）。
          roomName: 'メイン',
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '広場を作る',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _roomsEnabled,
                  title: const Text('寄合を複数作成する'),
                  subtitle: const Text(
                    'オフの場合、寄合は1つだけになりサイドバーは出ません。'
                    '設定は全てハンバーガーメニューから行えます（後から複数に切り替え可能）',
                  ),
                  onChanged: (value) => setState(() => _roomsEnabled = value),
                ),
                const SizedBox(height: 16),
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
        ),
      ],
    );
  }
}
