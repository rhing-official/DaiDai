import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_join_request.dart';
import '../../providers/repository_providers.dart';

/// 広場のメンバー一覧。長・モデレーターには、招待リンクからの参加リクエストの
/// 承認・却下UIもあわせて表示する。
class GroupMemberListScreen extends ConsumerWidget {
  const GroupMemberListScreen({
    required this.currentUser,
    required this.group,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final role = group.memberRoles[currentUser.userId];
    final canApprove = role == 'owner' || role == 'moderator';

    return Scaffold(
      appBar: AppBar(title: Text(strings.groupMemberListTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (canApprove) ...[
            _SectionHeader(strings.groupMemberListPendingSection),
            StreamBuilder<List<GroupJoinRequest>>(
              stream: ref.read(groupRepositoryProvider).watchJoinRequests(group.groupId),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? const [];
                if (requests.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    for (final request in requests)
                      _JoinRequestTile(request: request, strings: strings),
                  ],
                );
              },
            ),
            const Divider(height: 24),
          ],
          _SectionHeader(strings.groupMemberListMembersSection),
          FutureBuilder<List<AppUser>>(
            future: ref.read(userRepositoryProvider).getUsersByIds(group.memberIds),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final members = [...snapshot.data!]
                ..sort((a, b) => a.rhingId.compareTo(b.rhingId));
              return Column(
                children: [
                  for (final member in members)
                    _MemberTile(
                      user: member,
                      role: group.memberRoles[member.userId] ?? 'member',
                      vocab: vocab,
                      strings: strings,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _JoinRequestTile extends ConsumerWidget {
  const _JoinRequestTile({required this.request, required this.strings});

  final GroupJoinRequest request;
  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.person_add_alt_1_outlined),
      title: Text('@${request.requesterRhingId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => ref
                .read(groupRepositoryProvider)
                .respondToJoinRequest(request: request, accept: false),
            child: Text(strings.friendRequestDecline),
          ),
          FilledButton(
            onPressed: () => ref
                .read(groupRepositoryProvider)
                .respondToJoinRequest(request: request, accept: true),
            child: Text(strings.friendRequestAccept),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.user,
    required this.role,
    required this.vocab,
    required this.strings,
  });

  final AppUser user;
  final String role;
  final Vocabulary vocab;
  final Strings strings;

  String get _roleLabel => switch (role) {
        'owner' => vocab.owner,
        'moderator' => strings.groupRoleModerator,
        _ => strings.groupRoleMember,
      };

  @override
  Widget build(BuildContext context) {
    final iconUrl = user.effectiveIcon?.url;
    final nickname = user.effectiveNickname?.text;
    final label = (nickname?.isNotEmpty ?? false) ? nickname! : '@${user.rhingId}';
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        child: iconUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(label),
      trailing: Chip(label: Text(_roleLabel)),
    );
  }
}
