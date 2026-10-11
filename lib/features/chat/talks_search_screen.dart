import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/chat_room_message_cache.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../utils/open_conversation.dart';
import 'talks_search.dart';
import 'talks_tab.dart' show DirectMessageTile, GroupTile, dmSearchLabel;

/// モバイル実機＋アイコン＋寄合一覧レイアウト（`TalksListLayoutStyle
/// .iconSplit`）専用の語らい検索フルページ（2026-09-12追加）。112px幅の
/// アイコン列内ではインラインの検索結果表示が窮屈なため、検索アイコンの
/// タップでこの画面へ遷移する（`talks_tab.dart`の`_buildIconRail`参照）。
/// それ以外（標準レイアウト・コンピューター全般）は`talks_tab.dart`の
/// インライン検索のまま変わらない（要望1・4、`/talks/search`ルートの
/// docコメント参照）。
///
/// `TalksTab`から一覧のスナップショットを受け取らず、自前でRiverpodの
/// ストリームをwatchして常に最新のデータで検索する（`AnnouncementScreen`と
/// 同じ自己取得パターン）。検索アルゴリズム自体（3区分＋メッセージ内容検索）
/// は`talks_tab.dart`のインライン検索と共通（`talks_search.dart`参照）。
class TalksSearchScreen extends ConsumerStatefulWidget {
  const TalksSearchScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<TalksSearchScreen> createState() => _TalksSearchScreenState();
}

class _TalksSearchScreenState extends ConsumerState<TalksSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _messageSearchSession = TalksMessageSearchSession();
  Timer? _messageSearchDebounce;
  List<MessageSearchHit> _messageMatches = const [];

  /// デバウンスコールバック（build()の外）から参照するための、直近の
  /// build()時点のスナップショット（`_TalksTabState`と同じ理由）。
  List<DirectMessage> _lastDirectMessages = const [];
  List<Group> _lastGroups = const [];
  Set<String> _lastBlockedIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _messageSearchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchTextChanged() {
    setState(() {});
    _messageSearchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < kMinMessageSearchQueryLength) {
      _messageSearchSession.clear();
      if (_messageMatches.isNotEmpty) {
        setState(() => _messageMatches = const []);
      }
      return;
    }
    _messageSearchDebounce = Timer(kMessageSearchDebounce, () async {
      // `talks_tab.dart`の`_onSearchTextChanged`と同じ理由（2026-09-13追加）。
      List<MessageSearchHit> hits;
      try {
        hits = await _messageSearchSession.search(
          query: query,
          currentUserId: widget.currentUser.userId,
          directMessages: _lastDirectMessages,
          groups: _lastGroups,
          blockedIds: _lastBlockedIds,
          dmRepository: ref.read(directMessageRepositoryProvider),
          groupRepository: ref.read(groupRepositoryProvider),
          cacheManager: ref.read(chatRoomMessageCacheManagerProvider),
        );
      } catch (error, stackTrace) {
        debugPrint('メッセージ検索に失敗: $error\n$stackTrace');
        hits = const [];
      }
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _messageMatches = hits);
    });
  }

  // 一対・広場・メッセージ内容一致のタップは、`/chat/*`へ直接pushせず語らい
  // タブへ戻して設定どおりの見え方（アイコン＋寄合一覧）で開く（2026-10-11変更、
  // 以前は常にフルスクリーン＋寄合タブバーで開いていた）。
  Future<void> _openDm(DirectMessage dm) => openDmInTalks(ref, dm);

  Future<void> _openGroup(Group group) => openGroupInTalks(ref, group);

  /// メッセージ内容一致のタップ。該当メッセージまでのジャンプ＆ハイライトは
  /// `TalksTab._openMessageSearchHit`が[pendingMessageJumpProvider]経由で処理する。
  Future<void> _openMessageHit(MessageSearchHit hit) async =>
      openMessageHitInTalks(ref, hit);

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUser.userId);
    final groupsStream = ref
        .watch(groupRepositoryProvider)
        .watchGroups(widget.currentUser.userId);
    final blockedIds =
        ref.watch(blockedUserIdsProvider(widget.currentUser.userId)).value ??
        const {};
    final prefsById =
        ref.watch(conversationPrefsProvider(widget.currentUser.userId)).value ??
        const {};

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          decoration: InputDecoration(
            hintText: strings.talksSearchHint,
            border: InputBorder.none,
          ),
          onChanged: (_) => _onSearchTextChanged(),
        ),
      ),
      body: StreamBuilder<List<DirectMessage>>(
        stream: directMessagesStream,
        builder: (context, dmSnapshot) {
          final directMessages = dmSnapshot.data ?? [];
          return StreamBuilder<List<Group>>(
            stream: groupsStream,
            builder: (context, groupSnapshot) {
              final groups = groupSnapshot.data ?? [];
              _lastDirectMessages = directMessages;
              _lastGroups = groups;
              _lastBlockedIds = blockedIds;

              final query = _searchController.text;
              if (query.trim().isEmpty) {
                return const SizedBox.shrink();
              }

              final sections = computeTalksSearchSections(
                query: query,
                directMessages: directMessages,
                groups: groups,
                blockedIds: blockedIds,
                currentUserId: widget.currentUser.userId,
                dmLabelResolver: (dm) {
                  final otherUser = ref
                      .watch(
                        watchedUserProvider(
                          dm.otherUserId(widget.currentUser.userId),
                        ),
                      )
                      .value;
                  return dmSearchLabel(
                    otherUser,
                    dm,
                    widget.currentUser.userId,
                  );
                },
                messageMatches: _messageMatches,
              );

              return TalksSearchResultsView(
                sections: sections,
                dmSectionLabel: vocab.dm,
                groupSectionLabel: vocab.plaza,
                messageSectionLabel: strings.talksSearchSectionMessages,
                noResultsLabel: strings.talksSearchNoResults,
                isGekiga: isGekiga,
                dmTileBuilder: (context, dm) => DirectMessageTile(
                  currentUser: widget.currentUser,
                  dm: dm,
                  pinned: prefsById[dm.dmId]?.pinned ?? false,
                  muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
                  unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
                  onTap: () => _openDm(dm),
                ),
                groupTileBuilder: (context, group) => GroupTile(
                  currentUserId: widget.currentUser.userId,
                  group: group,
                  pinned: prefsById[group.groupId]?.pinned ?? false,
                  muted: prefsById[group.groupId]?.notificationsMuted ?? false,
                  unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
                  onTap: () => _openGroup(group),
                ),
                messageTileBuilder: (context, hit) => MessageSearchHitTile(
                  currentUser: widget.currentUser,
                  hit: hit,
                  onTap: () => _openMessageHit(hit),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
