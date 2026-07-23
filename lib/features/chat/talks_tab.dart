import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';

enum _TalksCategory { dm, group }

/// 語らいタブの中身。上部の「一対」「広場」を横並びで切り替えて一覧表示する。
/// 相手の追加・広場の作成は、この画面内の＋ボタン（中央ポップアップ）から行う。
class TalksTab extends ConsumerStatefulWidget {
  const TalksTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<TalksTab> createState() => _TalksTabState();
}

class _TalksTabState extends ConsumerState<TalksTab> {
  _TalksCategory _category = _TalksCategory.dm;

  void _openDirectMessage(DirectMessage dm) {
    ref.read(goRouterProvider).push(
      '/chat/dm',
      extra: DmChatArgs(currentUser: widget.currentUser, dm: dm),
    );
  }

  void _openGroup(Group group) {
    ref.read(goRouterProvider).push(
      '/chat/group',
      extra: GroupChatArgs(currentUser: widget.currentUser, group: group),
    );
  }

  void _openAddChat() {
    ref.read(goRouterProvider).push('/add-chat', extra: widget.currentUser);
  }

  void _openCreateGroup() {
    ref.read(goRouterProvider).push('/create-group', extra: widget.currentUser);
  }

  Future<void> _showAddMenu() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '語らいを追加',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_add_outlined),
                    title: const Text('一対を始める'),
                    subtitle: const Text('1対1で話す相手を追加する'),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _openAddChat();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('広場を作る'),
                    subtitle: const Text('3人以上のグループを作る'),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _openCreateGroup();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 少し行き過ぎてから戻る、弾むような「ポップ」演出。
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsStream = ref
        .watch(groupRepositoryProvider)
        .watchGroups(widget.currentUser.userId);
    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUser.userId);

    return Scaffold(
      body: StreamBuilder<List<DirectMessage>>(
        stream: directMessagesStream,
        builder: (context, dmSnapshot) {
          final directMessages = dmSnapshot.data ?? [];
          return StreamBuilder<List<Group>>(
            stream: groupsStream,
            builder: (context, groupSnapshot) {
              final groups = groupSnapshot.data ?? [];

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        _CategoryTab(
                          label: '一対',
                          count: directMessages.length,
                          selected: _category == _TalksCategory.dm,
                          onTap: () =>
                              setState(() => _category = _TalksCategory.dm),
                        ),
                        const SizedBox(width: 20),
                        _CategoryTab(
                          label: '広場',
                          count: groups.length,
                          selected: _category == _TalksCategory.group,
                          onTap: () => setState(
                            () => _category = _TalksCategory.group,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _showAddMenu,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _category == _TalksCategory.dm
                        ? _buildDirectMessages(dmSnapshot, directMessages)
                        : _buildGroups(groupSnapshot, groups),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDirectMessages(
    AsyncSnapshot<List<DirectMessage>> snapshot,
    List<DirectMessage> directMessages,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (directMessages.isEmpty) {
      return const Center(child: Text('まだ一対がありません。上の＋から相手を追加してください。'));
    }
    return ListView.builder(
      itemCount: directMessages.length,
      itemBuilder: (context, index) {
        final dm = directMessages[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text('@${dm.otherRhingId(widget.currentUser.userId)}'),
          onTap: () => _openDirectMessage(dm),
        );
      },
    );
  }

  Widget _buildGroups(AsyncSnapshot<List<Group>> snapshot, List<Group> groups) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty) {
      return const Center(child: Text('まだ広場がありません。上の＋から作成してください。'));
    }
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.groups)),
          title: Text(group.name),
          subtitle: Text('${group.memberIds.length}人'),
          onTap: () => _openGroup(group),
        );
      },
    );
  }
}

/// 「一対」「広場」を横並びで切り替えるタブ。件数チップ付き。
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
