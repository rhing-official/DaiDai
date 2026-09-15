import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/chat_room_message_cache.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/user_providers.dart';
import '../../repositories/direct_message_repository.dart';
import '../../repositories/group_repository.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/message_time.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/glass/glass_avatar.dart';
import '../../widgets/glass/glass_surface.dart';
import 'talks_tab.dart' show dmSearchLabel;

/// メッセージ内容検索でヒットした1件（2026-09-12追加）。[isDm]がtrueなら
/// [dm]、falseなら[group]のどちらか一方だけが設定される。
class MessageSearchHit {
  const MessageSearchHit({
    required this.message,
    required this.isDm,
    required this.roomId,
    this.dm,
    this.group,
  }) : assert(
         (isDm && dm != null && group == null) ||
             (!isDm && group != null && dm == null),
       );

  final Message message;
  final bool isDm;
  final DirectMessage? dm;
  final Group? group;
  final String roomId;
}

/// [computeTalksSearchSections]の計算結果。一対・広場・メッセージの3区分。
class TalksSearchSections {
  const TalksSearchSections({
    required this.dmMatches,
    required this.groupMatches,
    required this.messageMatches,
  });

  static const empty = TalksSearchSections(
    dmMatches: [],
    groupMatches: [],
    messageMatches: [],
  );

  final List<DirectMessage> dmMatches;
  final List<Group> groupMatches;
  final List<MessageSearchHit> messageMatches;

  bool get isEmpty =>
      dmMatches.isEmpty && groupMatches.isEmpty && messageMatches.isEmpty;
}

/// 一対名・広場名の一致を計算する純粋関数（`ref`に依存しない）。従来の
/// `_buildSearchResults`/`_buildIconRail`が個別に持っていたフィルタロジックを
/// 統合した（2026-09-12）。メッセージ内容の一致は非同期（[TalksMessageSearchSession]）
/// のため、計算済みの[messageMatches]をそのまま受け取って詰め直すだけに留める。
TalksSearchSections computeTalksSearchSections({
  required String query,
  required List<DirectMessage> directMessages,
  required List<Group> groups,
  required Set<String> blockedIds,
  required String currentUserId,
  required String Function(DirectMessage dm) dmLabelResolver,
  List<MessageSearchHit> messageMatches = const [],
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return const TalksSearchSections(
      dmMatches: [],
      groupMatches: [],
      messageMatches: [],
    );
  }
  final dmMatches = directMessages.where((dm) {
    final otherUserId = dm.otherUserId(currentUserId);
    if (blockedIds.contains(otherUserId)) return false;
    return dmLabelResolver(dm).toLowerCase().contains(normalizedQuery);
  }).toList();
  final groupMatches = groups
      .where((g) => g.name.toLowerCase().contains(normalizedQuery))
      .toList();
  return TalksSearchSections(
    dmMatches: dmMatches,
    groupMatches: groupMatches,
    messageMatches: messageMatches,
  );
}

/// メッセージ内容検索でヒット扱いにする最小クエリ文字数（2026-09-12追加）。
/// 1文字だけでは対象語らい全件に対するFirestore取得が無駄に発生するため、
/// これ未満の間は取得自体を行わない。
const kMinMessageSearchQueryLength = 2;

/// 検索欄の入力から実際にメッセージ内容検索を実行するまでのデバウンス
/// （`chat_screen.dart`の`_suggestionDebounceTimer`と同じ考え方）。
const kMessageSearchDebounce = Duration(milliseconds: 400);

/// 1つの寄合あたり、メッセージ内容検索のために1回だけ取得する最大件数。
/// 2026-09-14: 検索対象が会話1件→既定の寄合1件から会話1件→全寄合に
/// 広がった（寄合が多い会話ほど合計の取得件数が増える）ため、200→100へ
/// 引き下げてコストを緩和した。
const kMessageSearchPerRoomLimit = 100;

/// メッセージ内容検索結果の最大表示件数。
const kMessageSearchMaxResults = 50;

/// メッセージ内容検索の実行と、検索セッション内でのみ有効な取得済み
/// メッセージのメモ化キャッシュを持つヘルパー（2026-09-12追加、ウィジェット
/// ではない素のクラス）。サーバー側の全文検索インデックスは持たない方針
/// （プライバシーファースト＋フェーズ2のE2E暗号化方針と矛盾するため）のため、
/// Firestoreからバルク取得した結果をここでクライアント側フィルタする。
///
/// 各会話（一対/広場）が持つ**全ての寄合**を検索対象にする（2026-09-14
/// 変更。以前は各会話の既定の寄合（defaultRoomId）1つだけが対象だったが、
/// 「既定の寄合」はユーザーから不可視・変更不可の内部実装で、それ以外の
/// 寄合に送ったメッセージが検索にヒットしないのは体験として壊れていると
/// 判断し、会話が持つ全寄合を対象に広げた）。
///
/// 検索欄を開いている間（検索UIのState 1つにつき1インスタンス）だけ
/// 生存させ、`clear()`で取得済みメッセージ・寄合一覧のメモ化を破棄する。
/// 同じ会話・同じ寄合を2回以上検索した場合、2回目以降はFirestoreへ
/// 再取得しない。
class TalksMessageSearchSession {
  final _fetchedByRoomKey = <ChatRoomCacheKey, List<Message>>{};
  final _dmRoomIdsByDmId = <String, List<String>>{};
  final _groupRoomIdsByGroupId = <String, List<String>>{};

  void clear() {
    _fetchedByRoomKey.clear();
    _dmRoomIdsByDmId.clear();
    _groupRoomIdsByGroupId.clear();
  }

  Future<List<Message>> _messagesForRoom({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required ChatRoomMessageCacheManager cacheManager,
    required Future<List<Message>> Function() fetch,
  }) async {
    final key = ChatRoomCacheKey(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    );
    final cached = _fetchedByRoomKey[key];
    if (cached != null) return cached;
    final liveEntry = cacheManager.peek(key);
    if (liveEntry != null &&
        (liveEntry.liveTailMessages.isNotEmpty ||
            liveEntry.olderMessages.isNotEmpty)) {
      final messages = [
        ...liveEntry.olderMessages,
        ...liveEntry.liveTailMessages,
      ];
      _fetchedByRoomKey[key] = messages;
      return messages;
    }
    final fetched = await fetch();
    _fetchedByRoomKey[key] = fetched;
    return fetched;
  }

  bool _matches(Message message, String normalizedQuery, String currentUserId) {
    if (message.contentType != 'text') return false;
    if (message.hiddenFor.contains(currentUserId)) return false;
    return message.content.toLowerCase().contains(normalizedQuery);
  }

  DateTime _sentAtOf(MessageSearchHit hit) =>
      hit.message.sentAt?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// この一対が持つ寄合IDの一覧をセッション内でメモ化して返す（2026-09-14
  /// 追加）。`watchRooms`はStreamしか提供しないため、既存コード
  /// （`talks_search_screen.dart`の`_openDm`等）と同じ`.first`で1回分だけ
  /// 取り出す。
  Future<List<String>> _roomIdsForDm(
    DirectMessage dm,
    DirectMessageRepository dmRepository,
    String currentUserId,
  ) async {
    final cached = _dmRoomIdsByDmId[dm.dmId];
    if (cached != null) return cached;
    final rooms = await dmRepository
        .watchRooms(dmId: dm.dmId, userId: currentUserId)
        .first;
    final roomIds = [for (final room in rooms) room.roomId];
    _dmRoomIdsByDmId[dm.dmId] = roomIds;
    return roomIds;
  }

  /// [_roomIdsForDm]の広場版。
  Future<List<String>> _roomIdsForGroup(
    Group group,
    GroupRepository groupRepository,
    String currentUserId,
  ) async {
    final cached = _groupRoomIdsByGroupId[group.groupId];
    if (cached != null) return cached;
    final rooms = await groupRepository
        .watchRooms(groupId: group.groupId, userId: currentUserId)
        .first;
    final roomIds = [for (final room in rooms) room.roomId];
    _groupRoomIdsByGroupId[group.groupId] = roomIds;
    return roomIds;
  }

  /// 一対の1つの寄合を検索する。1つの寄合の読み取りに失敗しても、同じ一対の
  /// 他の寄合・他の会話の検索を巻き込まないよう、ここで例外を捕捉し空リストに
  /// フォールバックする（2026-09-13追加。移行漏れの寄合や壊れた/レガシーな
  /// メッセージドキュメントが1件でもあると`Message.fromJson`等が例外を
  /// 投げ、以前は`Future.wait`ごと失敗して検索結果が恒久的に空になる
  /// 不具合があった。2026-09-14: 対象が会話1件→寄合1件から会話1件→
  /// 全寄合に広がったのに合わせて、寄合単位で捕捉するよう変更）。
  Future<List<MessageSearchHit>> _searchDmRoom(
    DirectMessage dm,
    String roomId,
    String normalizedQuery,
    String currentUserId,
    DirectMessageRepository dmRepository,
    ChatRoomMessageCacheManager cacheManager,
  ) async {
    try {
      final messages = await _messagesForRoom(
        isDm: true,
        conversationId: dm.dmId,
        roomId: roomId,
        cacheManager: cacheManager,
        fetch: () => dmRepository.getRecentMessagesForSearch(
          dmId: dm.dmId,
          roomId: roomId,
          limit: kMessageSearchPerRoomLimit,
        ),
      );
      return [
        for (final message in messages)
          if (_matches(message, normalizedQuery, currentUserId))
            MessageSearchHit(
              message: message,
              isDm: true,
              dm: dm,
              roomId: roomId,
            ),
      ];
    } catch (error, stackTrace) {
      debugPrint('メッセージ検索: 一対${dm.dmId}の寄合$roomIdの取得に失敗: $error\n$stackTrace');
      return const [];
    }
  }

  /// [_searchDmRoom]の広場版。
  Future<List<MessageSearchHit>> _searchGroupRoom(
    Group group,
    String roomId,
    String normalizedQuery,
    String currentUserId,
    GroupRepository groupRepository,
    ChatRoomMessageCacheManager cacheManager,
  ) async {
    try {
      final messages = await _messagesForRoom(
        isDm: false,
        conversationId: group.groupId,
        roomId: roomId,
        cacheManager: cacheManager,
        fetch: () => groupRepository.getRoomRecentMessagesForSearch(
          groupId: group.groupId,
          roomId: roomId,
          limit: kMessageSearchPerRoomLimit,
        ),
      );
      return [
        for (final message in messages)
          if (_matches(message, normalizedQuery, currentUserId))
            MessageSearchHit(
              message: message,
              isDm: false,
              group: group,
              roomId: roomId,
            ),
      ];
    } catch (error, stackTrace) {
      debugPrint(
        'メッセージ検索: 広場${group.groupId}の寄合$roomIdの取得に失敗: $error\n$stackTrace',
      );
      return const [];
    }
  }

  /// 1件の一対が持つ全ての寄合を検索する（2026-09-14変更、以前は
  /// 既定の寄合1つだけが対象だった）。寄合一覧の取得自体が失敗した場合も
  /// 検索全体を巻き込まないよう、ここで例外を捕捉し空リスト（この一対だけ
  /// 検索結果から漏れる）にフォールバックする。
  Future<List<MessageSearchHit>> _searchDm(
    DirectMessage dm,
    String normalizedQuery,
    String currentUserId,
    DirectMessageRepository dmRepository,
    ChatRoomMessageCacheManager cacheManager,
  ) async {
    List<String> roomIds;
    try {
      roomIds = await _roomIdsForDm(dm, dmRepository, currentUserId);
    } catch (error, stackTrace) {
      debugPrint('メッセージ検索: 一対${dm.dmId}の寄合一覧取得に失敗: $error\n$stackTrace');
      return const [];
    }
    final results = await Future.wait([
      for (final roomId in roomIds)
        _searchDmRoom(
          dm,
          roomId,
          normalizedQuery,
          currentUserId,
          dmRepository,
          cacheManager,
        ),
    ]);
    return [for (final list in results) ...list];
  }

  /// [_searchDm]の広場版。
  Future<List<MessageSearchHit>> _searchGroup(
    Group group,
    String normalizedQuery,
    String currentUserId,
    GroupRepository groupRepository,
    ChatRoomMessageCacheManager cacheManager,
  ) async {
    List<String> roomIds;
    try {
      roomIds = await _roomIdsForGroup(group, groupRepository, currentUserId);
    } catch (error, stackTrace) {
      debugPrint('メッセージ検索: 広場${group.groupId}の寄合一覧取得に失敗: $error\n$stackTrace');
      return const [];
    }
    final results = await Future.wait([
      for (final roomId in roomIds)
        _searchGroupRoom(
          group,
          roomId,
          normalizedQuery,
          currentUserId,
          groupRepository,
          cacheManager,
        ),
    ]);
    return [for (final list in results) ...list];
  }

  /// [directMessages]・[groups]それぞれが持つ**全ての寄合**を対象に
  /// メッセージ内容を検索する（2026-09-14変更、以前は既定の寄合1つだけが
  /// 対象だった）。ブロック済みの相手との一対は対象外にする（名前検索・
  /// 語らい一覧と同じ扱い）。
  Future<List<MessageSearchHit>> search({
    required String query,
    required String currentUserId,
    required List<DirectMessage> directMessages,
    required List<Group> groups,
    required Set<String> blockedIds,
    required DirectMessageRepository dmRepository,
    required GroupRepository groupRepository,
    required ChatRoomMessageCacheManager cacheManager,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.length < kMinMessageSearchQueryLength) return const [];

    final futures = <Future<List<MessageSearchHit>>>[
      for (final dm in directMessages)
        if (!blockedIds.contains(dm.otherUserId(currentUserId)))
          _searchDm(
            dm,
            normalizedQuery,
            currentUserId,
            dmRepository,
            cacheManager,
          ),
      for (final group in groups)
        _searchGroup(
          group,
          normalizedQuery,
          currentUserId,
          groupRepository,
          cacheManager,
        ),
    ];

    final results = await Future.wait(futures);
    final hits = [for (final list in results) ...list]
      ..sort((a, b) => _sentAtOf(b).compareTo(_sentAtOf(a)));
    return hits.take(kMessageSearchMaxResults).toList();
  }
}

/// 語らい検索結果の3区分（一対/広場/メッセージ）を描画する共有ウィジェット
/// （2026-09-12追加）。標準レイアウトのインライン検索結果・アイコン列の
/// インライン検索結果・モバイル専用フルページ検索画面の3箇所から使い回す。
/// DM/Group/メッセージそれぞれのタイルは呼び出し側が注入するため、フルサイズの
/// タイルとアイコン列向けの簡易タイルを使い分けられる。
class TalksSearchResultsView extends StatelessWidget {
  const TalksSearchResultsView({
    required this.sections,
    required this.dmSectionLabel,
    required this.groupSectionLabel,
    required this.messageSectionLabel,
    required this.noResultsLabel,
    required this.isGekiga,
    required this.dmTileBuilder,
    required this.groupTileBuilder,
    required this.messageTileBuilder,
    this.padding,
    super.key,
  });

  final TalksSearchSections sections;
  final String dmSectionLabel;
  final String groupSectionLabel;
  final String messageSectionLabel;
  final String noResultsLabel;
  final bool isGekiga;
  final Widget Function(BuildContext context, DirectMessage dm) dmTileBuilder;
  final Widget Function(BuildContext context, Group group) groupTileBuilder;
  final Widget Function(BuildContext context, MessageSearchHit hit)
  messageTileBuilder;
  final EdgeInsetsGeometry? padding;

  Widget _sectionHeader(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: isGekiga
            ? GekigaColors.onPanel
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Center(child: Text(noResultsLabel));
    }

    if (isGekiga) {
      return SingleChildScrollView(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sections.dmMatches.isNotEmpty) ...[
              _sectionHeader(context, dmSectionLabel),
              GekigaJointedTileList(
                seeds: [for (final dm in sections.dmMatches) dm.dmId.hashCode],
                selectedFlags: [for (final _ in sections.dmMatches) false],
                children: [
                  for (final dm in sections.dmMatches)
                    dmTileBuilder(context, dm),
                ],
              ),
            ],
            if (sections.groupMatches.isNotEmpty) ...[
              _sectionHeader(context, groupSectionLabel),
              GekigaJointedTileList(
                seeds: [
                  for (final group in sections.groupMatches)
                    group.groupId.hashCode,
                ],
                selectedFlags: [for (final _ in sections.groupMatches) false],
                children: [
                  for (final group in sections.groupMatches)
                    groupTileBuilder(context, group),
                ],
              ),
            ],
            if (sections.messageMatches.isNotEmpty) ...[
              _sectionHeader(context, messageSectionLabel),
              GekigaJointedTileList(
                seeds: [
                  for (final hit in sections.messageMatches)
                    hit.message.messageId.hashCode,
                ],
                selectedFlags: [for (final _ in sections.messageMatches) false],
                children: [
                  for (final hit in sections.messageMatches)
                    messageTileBuilder(context, hit),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8),
      children: [
        if (sections.dmMatches.isNotEmpty)
          _sectionHeader(context, dmSectionLabel),
        for (final dm in sections.dmMatches) dmTileBuilder(context, dm),
        if (sections.groupMatches.isNotEmpty)
          _sectionHeader(context, groupSectionLabel),
        for (final group in sections.groupMatches)
          groupTileBuilder(context, group),
        if (sections.messageMatches.isNotEmpty)
          _sectionHeader(context, messageSectionLabel),
        for (final hit in sections.messageMatches)
          messageTileBuilder(context, hit),
      ],
    );
  }
}

/// メッセージ内容検索のヒット1件分のタイル（2026-09-12追加）。会話名（相手の
/// 呼び名/広場名）と本文スニペットを表示する。[compact]はアイコン列
/// （112px幅）向けの簡易表示。
class MessageSearchHitTile extends ConsumerWidget {
  const MessageSearchHitTile({
    required this.currentUser,
    required this.hit,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final AppUser currentUser;
  final MessageSearchHit hit;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final otherUser = hit.isDm
        ? ref
              .watch(
                watchedUserProvider(hit.dm!.otherUserId(currentUser.userId)),
              )
              .value
        : null;
    final conversationLabel = hit.isDm
        ? dmSearchLabel(otherUser, hit.dm!, currentUser.userId)
        : hit.group!.name;
    final iconUrl = hit.isDm
        ? otherUser?.effectiveIconFor(hit.dm!.dmId)?.url
        : hit.group!.profileCard?.iconUrl;
    final snippet = messageSnippetOf(hit.message.content);
    final sentAt = hit.message.sentAt?.toDate();
    final timeLabel = sentAt == null
        ? null
        : formatConversationListTime(sentAt, DateTime.now(), timeFormat);

    final avatarRadius = compact ? 14.0 : 20.0;
    final avatarFallback = Icon(
      hit.isDm ? Icons.person : Icons.groups,
      size: compact ? 14 : 20,
      color: colorScheme.onSurfaceVariant,
    );
    final avatar = uiStyle == AppUiStyle.glass
        ? GlassAvatar(
            size: avatarRadius * 2,
            image: iconUrl != null ? NetworkImage(iconUrl) : null,
            fallback: iconUrl != null ? null : avatarFallback,
          )
        : CircleAvatar(
            radius: avatarRadius,
            backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
            backgroundColor: Colors.transparent,
            foregroundColor: colorScheme.onSurfaceVariant,
            child: iconUrl == null ? avatarFallback : null,
          );
    final titleWidget = Text(
      conversationLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final subtitleWidget = Text(
      snippet,
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
    final trailingWidget = compact || timeLabel == null
        ? null
        : Text(timeLabel, style: Theme.of(context).textTheme.bodySmall);

    switch (uiStyle) {
      case AppUiStyle.gekiga:
        return GekigaTileContent(
          leading: avatar,
          title: titleWidget,
          subtitle: subtitleWidget,
          trailing: trailingWidget,
          onTap: onTap,
        );
      case AppUiStyle.glass:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: compact,
              iconColor: colorScheme.onSurfaceVariant,
              textColor: colorScheme.onSurfaceVariant,
              leading: avatar,
              title: titleWidget,
              subtitle: subtitleWidget,
              trailing: trailingWidget,
              onTap: onTap,
            ),
          ),
        );
      case AppUiStyle.flat:
        return ListTile(
          dense: compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: avatar,
          title: titleWidget,
          subtitle: subtitleWidget,
          trailing: trailingWidget,
          onTap: onTap,
        );
    }
  }
}
