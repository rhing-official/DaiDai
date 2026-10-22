import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_call.dart';
import 'repository_providers.dart';

/// その広場で現在進行中の通話（あれば1件）をリアルタイムに参照する。
/// `GroupChatPane`のAppBarで「新規に通話を始める」か「進行中の通話に
/// 参加する」かをボタン押下時に切り替えるために使う。
///
/// 退出処理が走らずに`active`のまま残った通話（タブを閉じた等）は、誰も生きて
/// 残っていなければ`null`として扱い、後始末（終了扱い）も行う（2026-10-22）。
final activeGroupCallProvider = Provider.family<AsyncValue<GroupCall?>, String>(
  (ref, groupId) {
    final raw = ref.watch(_rawActiveGroupCallProvider(groupId));
    final call = raw.value;
    if (call == null) return raw;
    // ハートビート切れは時間経過で成立するため、定期的に再評価する。
    ref.watch(_presenceTickProvider);
    final participants = ref
        .watch(_callParticipantsProvider(call.groupCallId))
        .value;
    if (participants == null) return raw;
    if (isGroupCallAbandoned(
      participants: participants,
      createdAt: call.createdAt,
      now: DateTime.now(),
    )) {
      final repository = ref.read(groupCallRepositoryProvider);
      Future.microtask(
        () => repository.endGroupCallIfAbandoned(call.groupCallId).ignore(),
      );
      return const AsyncData<GroupCall?>(null);
    }
    return raw;
  },
);

final _rawActiveGroupCallProvider = StreamProvider.family<GroupCall?, String>((
  ref,
  groupId,
) {
  return ref.watch(groupCallRepositoryProvider).watchActiveGroupCall(groupId);
});

final _callParticipantsProvider =
    StreamProvider.family<List<CallParticipant>, String>((ref, groupCallId) {
      return ref
          .watch(groupCallRepositoryProvider)
          .watchParticipants(groupCallId);
    });

final _presenceTickProvider = StreamProvider<int>(
  (ref) => Stream.periodic(const Duration(seconds: 15), (i) => i),
);

/// 自分がメンバーになっている広場すべてを横断して、現在進行中の通話一覧を
/// 監視する。着信バナー（[GroupIncomingCallListener]）が新規に始まった
/// 通話を検知するために使う。
final activeGroupCallsForUserProvider =
    StreamProvider.family<List<GroupCall>, String>((ref, userId) {
      return ref
          .watch(groupCallRepositoryProvider)
          .watchActiveGroupCallsForMember(userId);
    });

/// 進行中の広場通話の、いまの参加人数（離脱扱いの人を除く）。通話ボタンの
/// バッジ表示に使う（2026-10-21）。
final groupCallParticipantCountProvider = StreamProvider.family<int, String>((
  ref,
  groupCallId,
) {
  return ref
      .watch(groupCallRepositoryProvider)
      .watchParticipants(groupCallId)
      .map(
        (participants) => liveParticipantCount(participants, DateTime.now()),
      );
});
