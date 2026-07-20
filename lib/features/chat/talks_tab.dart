import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import 'chat_screen.dart';

enum _TalksCategory { group, dm }

/// 語らいタブの中身。上部のポップアップで「広場」「一対」を切り替えて一覧表示する。
/// 相手の追加は+ボタンから別画面で行う。
class TalksTab extends ConsumerStatefulWidget {
  const TalksTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<TalksTab> createState() => _TalksTabState();
}

class _TalksTabState extends ConsumerState<TalksTab> {
  _TalksCategory _category = _TalksCategory.group;

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
            content: content,
          ),
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
  }

  Future<void> _pickCategory() async {
    final selected = await showMenu<_TalksCategory>(
      context: context,
      position: const RelativeRect.fromLTRB(16, 90, 16, 0),
      items: const [
        PopupMenuItem(value: _TalksCategory.group, child: Text('広場')),
        PopupMenuItem(value: _TalksCategory.dm, child: Text('一対')),
      ],
    );
    if (selected != null) {
      setState(() => _category = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsStream = ref
        .watch(groupRepositoryProvider)
        .watchGroups(widget.currentUser.userId);
    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUser.userId);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickCategory,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFEE7800)),
              iconAlignment: IconAlignment.end,
              label: Text(
                _category == _TalksCategory.group ? '広場' : '一対',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEE7800),
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _category == _TalksCategory.group
              ? StreamBuilder<List<Group>>(
                  stream: groupsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
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
                )
              : StreamBuilder<List<DirectMessage>>(
                  stream: directMessagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
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
                ),
        ),
      ],
    );
  }
}
