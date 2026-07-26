import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_join_request.dart';
import '../../providers/repository_providers.dart';
import 'user_profile_card_dialog.dart';

/// 広場のメンバー一覧（ポップアップの中身）。長・モデレーターには、招待リンクからの
/// 参加リクエストの承認・却下UIもあわせて表示する。メンバー本体を先に、
/// 招待中（承認待ち）は最下部にまとめて表示する。
class GroupMemberListPopup extends ConsumerWidget {
  const GroupMemberListPopup({
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.groupMemberListTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
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
                          currentUser: currentUser,
                          user: member,
                          role: group.memberRoles[member.userId] ?? 'member',
                          vocab: vocab,
                          strings: strings,
                        ),
                    ],
                  );
                },
              ),
              if (canApprove) ...[
                const Divider(height: 24),
                _SectionHeader(strings.groupMemberListPendingSection),
                StreamBuilder<List<GroupJoinRequest>>(
                  stream:
                      ref.read(groupRepositoryProvider).watchJoinRequests(group.groupId),
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
              ],
            ],
          ),
        ),
      ],
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

  // 以前はawaitもエラーハンドリングも無い投げっぱなしで、失敗しても
  // ボタンの見た目だけが反応して何も起きていないように見えた（承認・却下が
  // 実は失敗していても気付けなかった）。エラー時は画面に表示する。
  Future<void> _respond(BuildContext context, WidgetRef ref, bool accept) async {
    try {
      await ref
          .read(groupRepositoryProvider)
          .respondToJoinRequest(request: request, accept: accept);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.person_add_alt_1_outlined),
      title: Text('@${request.requesterRhingId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _respond(context, ref, false),
            child: Text(strings.friendRequestDecline),
          ),
          FilledButton(
            onPressed: () => _respond(context, ref, true),
            child: Text(strings.friendRequestAccept),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.currentUser,
    required this.user,
    required this.role,
    required this.vocab,
    required this.strings,
  });

  final AppUser currentUser;
  final AppUser user;
  final String role;
  final Vocabulary vocab;
  final Strings strings;

  // モデレーターという言葉自体は表示しない方針にしたため、モデレーターも
  // 通常のメンバーと同じラベルで表示する（権限自体は引き続き役割として持つ）。
  String get _roleLabel => switch (role) {
        'owner' => vocab.owner,
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
      // タップすると相手のプロフィールカードを見られ、友達でなければそこから
      // 友達申請を送れる（chat_screen.dartの送信者アイコンタップと同じ導線）。
      onTap: () =>
          UserProfileCardDialog.show(context, currentUser: currentUser, user: user),
    );
  }
}
