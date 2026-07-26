import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../models/friend_request.dart';
import '../../models/group.dart';
import '../../models/group_invite_preview.dart';
import '../../models/group_join_request.dart';
import '../../providers/block_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/friend_providers.dart';
import '../../providers/group_join_request_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../router/app_router.dart';
import '../../widgets/swipe_gestures.dart';
import 'chat_panes.dart';

enum _TalksCategory { dm, group }

/// 画面幅がこれ以上あれば、一覧と会話を左右分割で同時表示する
/// （Discordのような「一覧は常に見えたまま、選んだ会話が右隣に開く」構成）。
/// これ未満の狭い画面では、従来通り会話をフルスクリーンで開く。
const _kSplitBreakpoint = 760.0;

/// 語らいタブの中身。上部の「一対」「広場」を横並びで切り替えて一覧表示する。
/// 相手の追加・広場の作成は、この画面内の＋ボタン（中央ポップアップ）から行う。
/// 一対タブの最上部には、届いている／送った友達申請が会話より先に表示される
/// （承認されて実際に会話が始まると、通常の一対リストの方へ下がっていく）。
class TalksTab extends ConsumerStatefulWidget {
  const TalksTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<TalksTab> createState() => _TalksTabState();
}

class _TalksTabState extends ConsumerState<TalksTab> {
  _TalksCategory _category = _TalksCategory.dm;
  DirectMessage? _selectedDm;
  Group? _selectedGroup;

  /// 左右分割表示（[_isSplit]）の時、会話ペインを横いっぱいに広げて
  /// 一覧ペインを隠すか。横長のタブレット等で、固定幅の一覧に会話ペインの
  /// 幅を圧迫されず全画面で読みたい時のための切り替え。
  bool _chatExpanded = false;

  bool get _isSplit => MediaQuery.sizeOf(context).width >= _kSplitBreakpoint;

  void _openDirectMessage(DirectMessage dm) {
    if (_isSplit) {
      setState(() => _selectedDm = dm);
      return;
    }
    ref.read(goRouterProvider).push(
      '/chat/dm',
      extra: DmChatArgs(currentUser: widget.currentUser, dm: dm),
    );
  }

  void _openGroup(Group group) {
    if (_isSplit) {
      setState(() => _selectedGroup = group);
      return;
    }
    ref.read(goRouterProvider).push(
      '/chat/group',
      extra: GroupChatArgs(currentUser: widget.currentUser, group: group),
    );
  }

  Future<void> _startCall(DirectMessage dm, {bool isVideo = false}) async {
    final callRepository = ref.read(callRepositoryProvider);
    final other = AppUser(
      userId: dm.otherUserId(widget.currentUser.userId),
      rhingId: dm.otherRhingId(widget.currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: widget.currentUser,
      callee: other,
      isVideo: isVideo,
    );
    ref.read(goRouterProvider).push(
      '/call',
      extra: CallArgs(
        call: call,
        isCaller: true,
        currentUserId: widget.currentUser.userId,
      ),
    );
  }

  void _openAddChat() {
    ref.read(goRouterProvider).push('/add-chat', extra: widget.currentUser);
  }

  void _openCreateGroup() {
    ref.read(goRouterProvider).push('/create-group', extra: widget.currentUser);
  }

  Future<void> _showAddMenu() async {
    final strings = ref.read(appStringsProvider);
    final vocab = ref.read(vocabularyProvider);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: strings.navTalk,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        // 注意: DialogをMaterial(color: transparent)で余分に包むと、
        // その外側Materialがタップを吸収してしまいバリアの外側タップ dismiss が効かなくなる
        // （実装内容.mdの経緯参照）。Dialogを直接Centerの子にすること。
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: SwipeDownToDismiss(
              onDismiss: () => Navigator.of(dialogContext).pop(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_add_outlined),
                    title: Text(strings.addMenuDmTitleTemplate(vocab.dm)),
                    subtitle: Text(strings.addMenuDmSubtitle),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _openAddChat();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(strings.addMenuGroupTitleTemplate(vocab.plaza)),
                    subtitle: Text(strings.addMenuGroupSubtitle),
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
    final vocab = ref.watch(vocabularyProvider);
    final groupsStream = ref
        .watch(groupRepositoryProvider)
        .watchGroups(widget.currentUser.userId);
    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUser.userId);
    final incomingRequests =
        ref.watch(incomingFriendRequestsProvider(widget.currentUser.userId)).value ??
            const [];
    final outgoingRequests =
        ref.watch(outgoingFriendRequestsProvider(widget.currentUser.userId)).value ??
            const [];
    final prefsById =
        ref.watch(conversationPrefsProvider(widget.currentUser.userId)).value ??
            const {};
    final blockedIds =
        ref.watch(blockedUserIdsProvider(widget.currentUser.userId)).value ??
            const {};
    final pendingGroupRequests = ref
            .watch(myPendingGroupJoinRequestsProvider(widget.currentUser.userId))
            .value ??
        const [];

    final isSplit = _isSplit;

    return Scaffold(
      body: StreamBuilder<List<DirectMessage>>(
        stream: directMessagesStream,
        builder: (context, dmSnapshot) {
          final directMessages = dmSnapshot.data ?? [];
          return StreamBuilder<List<Group>>(
            stream: groupsStream,
            builder: (context, groupSnapshot) {
              final groups = groupSnapshot.data ?? [];

              final listPane = Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        // 用語スタイルによってはラベルが長くなる
                        // （例:「ダイレクトメッセージ」「Terminology & display」相当）ため、
                        // 固定幅のサイドバーでも折り返さず、必要なときだけ
                        // 横スクロールできるようにして＋ボタンが押し出されないようにする。
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _CategoryTab(
                                  label: vocab.dm,
                                  count: directMessages.length,
                                  selected: _category == _TalksCategory.dm,
                                  onTap: () => setState(
                                    () => _category = _TalksCategory.dm,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                _CategoryTab(
                                  label: vocab.plaza,
                                  count: groups.length,
                                  selected: _category == _TalksCategory.group,
                                  onTap: () => setState(
                                    () => _category = _TalksCategory.group,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filled(
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: _showAddMenu,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    // 横スワイプで一対⇄広場を切り替える。一対が先頭・広場が
                    // 2番目のタブなので、他タブの「前へ/次へ」パターンと同じ
                    // 向き（右スワイプ＝広場→一対、左スワイプ＝一対→広場）を
                    // そのまま流用する。戻る先の一覧が無いためonBackは空実装。
                    child: SwipeBackDetector(
                      onBack: () {},
                      onPrevious: _category == _TalksCategory.group
                          ? () => setState(() => _category = _TalksCategory.dm)
                          : null,
                      onNext: _category == _TalksCategory.dm
                          ? () => setState(() => _category = _TalksCategory.group)
                          : null,
                      child: _category == _TalksCategory.dm
                          ? _buildDirectMessages(
                              dmSnapshot,
                              directMessages,
                              incomingRequests,
                              outgoingRequests,
                              prefsById,
                              blockedIds,
                            )
                          : _buildGroups(
                              groupSnapshot,
                              groups,
                              prefsById,
                              pendingGroupRequests,
                            ),
                    ),
                  ),
                ],
              );

              if (!isSplit) return listPane;

              // 会話ペインでの横スワイプで一覧の表示/非表示を切り替える
              // （一覧側のスワイプは既に一対⇄広場の切り替えに使っているため、
              // ここは会話ペインのみに閉じたジェスチャーにする）。
              // 左スワイプ＝広げる、右スワイプ＝戻す、という他画面と同じ
              // 「進む/戻る」の向きに合わせている。
              final detailPane = SwipeBackDetector(
                onBack: () => setState(() => _chatExpanded = false),
                onNext: () => setState(() => _chatExpanded = true),
                child: _buildDetailPane(directMessages, groups),
              );

              if (_chatExpanded) return detailPane;

              return Row(
                children: [
                  SizedBox(width: 360, child: listPane),
                  const VerticalDivider(width: 1),
                  Expanded(child: detailPane),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 選択中の会話ペインを、その時点の会話一覧（Firestoreの最新スナップショット）
  /// から解決して構築する。`_selectedDm`/`_selectedGroup`は選択した瞬間の
  /// スナップショットのままなので、これをそのまま`DmChatPane`/`GroupChatPane`に
  /// 渡すと、選択後に相手側でプロフィールカード等を更新しても、一覧の再選択や
  /// 画面再読み込みをするまで古い内容のまま表示され続けてしまう（一覧自体は
  /// 各StreamBuilderで直接再描画されるため最新化されるが、選択状態はここでしか
  /// 保持していないため）。選択中IDに一致する最新の要素があればそちらを使う。
  Widget _buildDetailPane(
    List<DirectMessage> directMessages,
    List<Group> groups,
  ) {
    if (_category == _TalksCategory.dm) {
      final selected = _selectedDm;
      if (selected == null) return const _EmptyDetailPlaceholder();
      final dm = directMessages.firstWhere(
        (d) => d.dmId == selected.dmId,
        orElse: () => selected,
      );
      return DmChatPane(
        key: ValueKey('detail-dm-${dm.dmId}'),
        currentUser: widget.currentUser,
        dm: dm,
        onCallPressed: () => _startCall(dm),
        onVideoCallPressed: () => _startCall(dm, isVideo: true),
      );
    }
    final selected = _selectedGroup;
    if (selected == null) return const _EmptyDetailPlaceholder();
    final group = groups.firstWhere(
      (g) => g.groupId == selected.groupId,
      orElse: () => selected,
    );
    return GroupChatPane(
      key: ValueKey('detail-group-${group.groupId}'),
      currentUser: widget.currentUser,
      group: group,
    );
  }

  Widget _buildDirectMessages(
    AsyncSnapshot<List<DirectMessage>> snapshot,
    List<DirectMessage> directMessages,
    List<FriendRequest> incomingRequests,
    List<FriendRequest> outgoingRequests,
    Map<String, ConversationPrefs> prefsById,
    Set<String> blockedIds,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        incomingRequests.isEmpty &&
        outgoingRequests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // ブロックした相手は一対の一覧から非表示にする（会話・ブロック状態自体は
    // 保持したまま、一覧に出さないだけ。ブロック解除は設定＞語らいから行う）。
    final visibleDms = directMessages
        .where((dm) =>
            !blockedIds.contains(dm.otherUserId(widget.currentUser.userId)))
        .toList();
    if (visibleDms.isEmpty &&
        incomingRequests.isEmpty &&
        outgoingRequests.isEmpty) {
      final dmTerm = ref.read(vocabularyProvider).dm;
      return Center(child: Text('まだ$dmTermがありません。上の＋から相手を追加してください。'));
    }

    final sortedDms = _sortedByPin(
      visibleDms,
      prefsById,
      (dm) => dm.dmId,
    );

    return ListView(
      children: [
        for (final request in incomingRequests)
          _FriendRequestTile(currentUserId: widget.currentUser.userId, request: request),
        for (final request in outgoingRequests)
          _FriendRequestTile(currentUserId: widget.currentUser.userId, request: request),
        for (final dm in sortedDms)
          _DirectMessageTile(
            currentUser: widget.currentUser,
            dm: dm,
            pinned: prefsById[dm.dmId]?.pinned ?? false,
            muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedDm?.dmId == dm.dmId,
            onTap: () => _openDirectMessage(dm),
          ),
      ],
    );
  }

  Widget _buildGroups(
    AsyncSnapshot<List<Group>> snapshot,
    List<Group> groups,
    Map<String, ConversationPrefs> prefsById,
    List<GroupJoinRequest> pendingRequests,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        pendingRequests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty && pendingRequests.isEmpty) {
      final plazaTerm = ref.read(vocabularyProvider).plaza;
      return Center(child: Text('まだ$plazaTermがありません。上の＋から作成してください。'));
    }
    final sortedGroups = _sortedByPin(groups, prefsById, (g) => g.groupId);
    return ListView(
      children: [
        for (final request in pendingRequests)
          _PendingGroupJoinRequestTile(request: request),
        for (final group in sortedGroups)
          _GroupTile(
            currentUserId: widget.currentUser.userId,
            group: group,
            pinned: prefsById[group.groupId]?.pinned ?? false,
            muted: prefsById[group.groupId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedGroup?.groupId == group.groupId,
            onTap: () => _openGroup(group),
          ),
      ],
    );
  }

  static List<T> _sortedByPin<T>(
    List<T> items,
    Map<String, ConversationPrefs> prefsById,
    String Function(T) idOf,
  ) {
    final pinned = <T>[];
    final unpinned = <T>[];
    for (final item in items) {
      if (prefsById[idOf(item)]?.pinned ?? false) {
        pinned.add(item);
      } else {
        unpinned.add(item);
      }
    }
    return [...pinned, ...unpinned];
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

/// 届いている／送った友達申請を表す行。一対リストの最上部に表示される。
class _FriendRequestTile extends ConsumerWidget {
  const _FriendRequestTile({required this.currentUserId, required this.request});

  final String currentUserId;
  final FriendRequest request;

  bool get _isIncoming => request.toUserId == currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text('@${request.otherRhingId(currentUserId)}'),
      subtitle: Text(
        _isIncoming
            ? strings.friendRequestIncomingSubtitle
            : strings.friendRequestOutgoingSubtitle,
      ),
      trailing: _isIncoming
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(friendRepositoryProvider)
                      .respond(request: request, accept: false),
                  child: Text(strings.friendRequestDecline),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => ref
                      .read(friendRepositoryProvider)
                      .respond(request: request, accept: true),
                  child: Text(strings.friendRequestAccept),
                ),
              ],
            )
          : null,
    );
  }
}

/// 自分が送った、承認待ちの広場参加リクエストを一覧の先頭に表示するタイル。
/// タップしても実際の広場は開けない（まだメンバーではないため）ので、
/// 承認待ちであることを伝えるダイアログを出す。
class _PendingGroupJoinRequestTile extends ConsumerWidget {
  const _PendingGroupJoinRequestTile({required this.request});

  final GroupJoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return FutureBuilder<GroupInvitePreview?>(
      future: ref.read(groupRepositoryProvider).getInvitePreview(request.groupId),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage:
                preview?.iconUrl != null ? NetworkImage(preview!.iconUrl!) : null,
            child: preview?.iconUrl == null
                ? const Icon(Icons.hourglass_top_outlined)
                : null,
          ),
          title: Text(preview?.name ?? '...'),
          subtitle: Text(strings.groupJoinPendingListSubtitle),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(strings.groupJoinPending),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.groupJoinPendingDialogClose),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DirectMessageTile extends ConsumerWidget {
  const _DirectMessageTile({
    required this.currentUser,
    required this.dm,
    required this.pinned,
    required this.muted,
    required this.onTap,
    this.selected = false,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final bool pinned;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = dm.otherUserId(currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final nickname = otherUser?.effectiveNickname?.text;
    final label =
        (nickname?.isNotEmpty ?? false) ? nickname! : '@${dm.otherRhingId(currentUser.userId)}';
    final iconUrl = otherUser?.effectiveIcon?.url;

    return _ConversationGestures(
      conversationId: dm.dmId,
      userId: currentUser.userId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        leading: CircleAvatar(
          backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
          child: iconUrl == null ? const Icon(Icons.person) : null,
        ),
        title: Text(label),
        trailing: _ConversationIndicators(pinned: pinned, muted: muted),
        onTap: onTap,
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.currentUserId,
    required this.group,
    required this.pinned,
    required this.muted,
    required this.onTap,
    this.selected = false,
  });

  final String currentUserId;
  final Group group;
  final bool pinned;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconUrl = group.profileCard?.iconUrl;
    return _ConversationGestures(
      conversationId: group.groupId,
      userId: currentUserId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        leading: CircleAvatar(
          backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
          child: iconUrl == null ? const Icon(Icons.groups) : null,
        ),
        title: Text(group.name),
        subtitle: Text('${group.memberIds.length}人'),
        trailing: _ConversationIndicators(pinned: pinned, muted: muted),
        onTap: onTap,
      ),
    );
  }
}

/// ピン留め・通知オフのアイコン表示（両方falseなら何も出さない）。
class _ConversationIndicators extends StatelessWidget {
  const _ConversationIndicators({required this.pinned, required this.muted});

  final bool pinned;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (!pinned && !muted) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (muted) const Icon(Icons.notifications_off_outlined, size: 18, color: Colors.grey),
        if (pinned) ...[
          if (muted) const SizedBox(width: 4),
          Icon(Icons.push_pin, size: 18, color: Theme.of(context).colorScheme.primary),
        ],
      ],
    );
  }
}

/// 右クリック（デスクトップ）・長押し（モバイル）で、ピン留め・通知オフのメニューを出す。
class _ConversationGestures extends ConsumerWidget {
  const _ConversationGestures({
    required this.conversationId,
    required this.userId,
    required this.pinned,
    required this.muted,
    required this.child,
  });

  final String conversationId;
  final String userId;
  final bool pinned;
  final bool muted;
  final Widget child;

  Future<void> _showMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final strings = ref.read(appStringsProvider);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(pinned ? strings.conversationUnpin : strings.conversationPin),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(muted ? strings.conversationUnmute : strings.conversationMute),
        ),
      ],
    );
    if (selected == 'pin') {
      await ref.read(conversationPrefsRepositoryProvider).setPinned(
            userId: userId,
            conversationId: conversationId,
            pinned: !pinned,
          );
    } else if (selected == 'mute') {
      await ref.read(conversationPrefsRepositoryProvider).setNotificationsMuted(
            userId: userId,
            conversationId: conversationId,
            muted: !muted,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showMenu(context, ref, details.globalPosition),
      onLongPressStart: (details) => _showMenu(context, ref, details.globalPosition),
      child: child,
    );
  }
}

/// 分割ビューで会話が未選択のときに右側に表示するプレースホルダー。
class _EmptyDetailPlaceholder extends StatelessWidget {
  const _EmptyDetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.forum_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
