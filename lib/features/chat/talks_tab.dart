import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import 'chat_screen.dart';

/// 語らいタブの中身（広場一覧・縁側一覧）。相手の追加は+ボタンから別画面で行う。
class TalksTab extends ConsumerWidget {
  const TalksTab({required this.currentUser, super.key});

  final AppUser currentUser;

  void _openDirectMessage(
    BuildContext context,
    WidgetRef ref,
    DirectMessage dm,
  ) {
    final dmRepository = ref.read(directMessageRepositoryProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: '@${dm.otherRhingId(currentUser.userId)}',
          currentUserId: currentUser.userId,
          messagesStream: dmRepository.watchMessages(dm.dmId),
          onSend: (content) => dmRepository.sendTextMessage(
            dmId: dm.dmId,
            senderId: currentUser.userId,
            content: content,
          ),
        ),
      ),
    );
  }

  void _openGroup(BuildContext context, WidgetRef ref, Group group) {
    final groupRepository = ref.read(groupRepositoryProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: group.name,
          currentUserId: currentUser.userId,
          messagesStream: groupRepository.watchRoomMessages(
            group.groupId,
            group.defaultRoomId,
          ),
          onSend: (content) => groupRepository.sendRoomMessage(
            groupId: group.groupId,
            roomId: group.defaultRoomId,
            senderId: currentUser.userId,
            content: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsStream =
        ref.watch(groupRepositoryProvider).watchGroups(currentUser.userId);
    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(currentUser.userId);

    return StreamBuilder<List<Group>>(
      stream: groupsStream,
      builder: (context, groupSnapshot) {
        final groups = groupSnapshot.data ?? [];

        return StreamBuilder<List<DirectMessage>>(
          stream: directMessagesStream,
          builder: (context, dmSnapshot) {
            final directMessages = dmSnapshot.data ?? [];

            if (groupSnapshot.connectionState == ConnectionState.waiting &&
                dmSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (groups.isEmpty && directMessages.isEmpty) {
              return const Center(
                child: Text('まだ語らいがありません。右下の＋から相手を追加してください。'),
              );
            }

            return ListView(
              children: [
                if (groups.isNotEmpty) ...[
                  const _SectionHeader('広場'),
                  for (final group in groups)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(group.name),
                      subtitle: Text('${group.memberIds.length}人'),
                      onTap: () => _openGroup(context, ref, group),
                    ),
                ],
                if (directMessages.isNotEmpty) ...[
                  const _SectionHeader('縁側'),
                  for (final dm in directMessages)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text('@${dm.otherRhingId(currentUser.userId)}'),
                      onTap: () => _openDirectMessage(context, ref, dm),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFFEE7800),
        ),
      ),
    );
  }
}
