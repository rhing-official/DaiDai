import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/call/active_call_session.dart';
import '../models/call.dart';
import '../models/group_call.dart';
import 'group_call_providers.dart';
import 'repository_providers.dart';

/// 通話に入っている1人（アイコンと呼び名を出すための最小限の情報）。
class CallPresenceUser {
  const CallPresenceUser({required this.userId, required this.rhingSeed});

  final String userId;
  final String rhingSeed;
}

/// ある語らい（一対・広場）で、今進行中の通話（2026-11-17）。語らい一覧の箱・寄合一覧・
/// 広場のバナーで「通話中」と誰が入っているかを出すために使う。通話は広場単位・一対単位で、
/// 寄合には属さない。
class ConversationCallPresence {
  const ConversationCallPresence({
    required this.users,
    required this.isVideo,
    required this.isMine,
  });

  /// 通話に入っている人。読み込み中は空（通話があること自体は分かる）。
  final List<CallPresenceUser> users;
  final bool isVideo;

  /// 自分がこの通話に参加中か。
  final bool isMine;
}

/// 自分が発信側・着信側で今つながっている一対の通話（別の端末で参加中のものを含む）。
final myActiveOneToOneCallsProvider = StreamProvider<List<Call>>((ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return Stream.value(const []);
  return ref.watch(callRepositoryProvider).watchMyActiveCalls(userId);
});

/// 会話id（一対はdmId、広場はgroupId）の進行中の通話。無ければnull。
final conversationCallProvider =
    Provider.family<ConversationCallPresence?, String>((ref, conversationId) {
      final session = ref.watch(activeCallSessionProvider);
      final sessionConversationId = switch (session) {
        OneToOneCallSession(:final call) => call.dmId,
        GroupCallSession(:final groupId) => groupId,
        _ => null,
      };

      // 広場。
      final userId = ref.watch(authStateProvider).value?.uid;
      if (userId != null) {
        final calls = ref.watch(activeGroupCallsForUserProvider(userId)).value;
        final call = calls
            ?.where((c) => c.groupId == conversationId)
            .firstOrNull;
        if (call != null) {
          ref.watch(callPresenceTickProvider);
          final participants = ref
              .watch(groupCallParticipantsProvider(call.groupCallId))
              .value;
          final now = DateTime.now();
          if (participants != null &&
              isGroupCallAbandoned(
                participants: participants,
                createdAt: call.createdAt,
                now: now,
              )) {
            return null;
          }
          final live = participants == null
              ? const <CallParticipant>[]
              : liveParticipants(participants, now);
          return ConversationCallPresence(
            users: [
              for (final p in live)
                CallPresenceUser(userId: p.userId, rhingSeed: p.rhingSeed),
            ],
            isVideo: call.isVideo,
            isMine:
                sessionConversationId == conversationId ||
                live.any((p) => p.userId == userId),
          );
        }
      }

      // 一対。
      Call? active;
      if (session is OneToOneCallSession &&
          session.call.dmId == conversationId) {
        active = session.call;
      } else {
        final mine = ref.watch(myActiveOneToOneCallsProvider).value;
        active = mine?.where((c) => c.dmId == conversationId).firstOrNull;
      }
      if (active == null) return null;
      return ConversationCallPresence(
        users: [
          CallPresenceUser(
            userId: active.callerId,
            rhingSeed: active.callerRhingSeed,
          ),
          CallPresenceUser(
            userId: active.calleeId,
            rhingSeed: active.calleeRhingSeed,
          ),
        ],
        isVideo: active.isVideo,
        isMine: sessionConversationId == conversationId,
      );
    });
