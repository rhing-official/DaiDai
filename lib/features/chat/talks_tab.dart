import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import '../call/call_screen.dart';
import 'add_chat_screen.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';

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
    final dmRepository = ref.read(directMessageRepositoryProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: '@${dm.otherRhingId(widget.currentUser.userId)}',
          currentUserId: widget.currentUser.userId,
          messagesStream: dmRepository.watchMessages(dm.dmId),
          onSend: (content) => dmRepository.sendTextMessage(
            dmId: dm.dmId,
            senderId: widget.currentUser.userId,
            senderRhingId: widget.currentUser.rhingId,
            content: content,
          ),
          onCallPressed: () => _startCall(dm),
        ),
      ),
    );
  }

  Future<void> _startCall(DirectMessage dm) async {
    final callRepository = ref.read(callRepositoryProvider);
    final other = AppUser(
      userId: dm.otherUserId(widget.currentUser.userId),
      rhingId: dm.otherRhingId(widget.currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: widget.currentUser,
      callee: other,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          call: call,
          isCaller: true,
          currentUserId: widget.currentUser.userId,
        ),
      ),
    );
  }

  void _openGroup(Group group) {
    final groupRepository = ref.read(groupRepositoryProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: group.name,
          currentUserId: widget.currentUser.userId,
          showSenderAvatar: true,
          messagesStream: groupRepository.watchRoomMessages(
            group.groupId,
            group.defaultRoomId,
          ),
          onSend: (content) => groupRepository.sendRoomMessage(
            groupId: group.groupId,
            roomId: group.defaultRoomId,
            senderId: widget.currentUser.userId,
            senderRhingId: widget.currentUser.rhingId,
            content: content,
          ),
        ),
      ),
    );
  }

  void _openAddChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddChatScreen(currentUser: widget.currentUser),
      ),
    );
  }

  void _openCreateGroup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(currentUser: widget.currentUser),
      ),
    );
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _CategoryTab(
                  label: '一対',
                  selected: _category == _TalksCategory.dm,
                  onTap: () =>
                      setState(() => _category = _TalksCategory.dm),
                ),
                const SizedBox(width: 20),
                _CategoryTab(
                  label: '広場',
                  selected: _category == _TalksCategory.group,
                  onTap: () =>
                      setState(() => _category = _TalksCategory.group),
                ),
              ],
            ),
          ),
          Expanded(
            child: _category == _TalksCategory.dm
                ? StreamBuilder<List<DirectMessage>>(
                    stream: directMessagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final directMessages = snapshot.data ?? [];
                      if (directMessages.isEmpty) {
                        return const Center(
                          child: Text('まだ一対がありません。右下の＋から相手を追加してください。'),
                        );
                      }
                      return ListView.builder(
                        itemCount: directMessages.length,
                        itemBuilder: (context, index) {
                          final dm = directMessages[index];
                          return ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(
                              '@${dm.otherRhingId(widget.currentUser.userId)}',
                            ),
                            onTap: () => _openDirectMessage(dm),
                          );
                        },
                      );
                    },
                  )
                : StreamBuilder<List<Group>>(
                    stream: groupsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final groups = snapshot.data ?? [];
                      if (groups.isEmpty) {
                        return const Center(
                          child: Text('まだ広場がありません。右下の＋から作成してください。'),
                        );
                      }
                      return ListView.builder(
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.groups)),
                            title: Text(group.name),
                            subtitle: Text('${group.memberIds.length}人'),
                            onTap: () => _openGroup(group),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 「一対」「広場」を横並びで切り替えるタブ。
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: color,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
