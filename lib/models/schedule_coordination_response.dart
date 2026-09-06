import 'package:cloud_firestore/cloud_firestore.dart';

import 'schedule_coordination.dart';

/// [ScheduleCoordination]1件・住人1人ごとの回答
/// (`.../scheduleCoordinations/{coordinationId}/responses/{uid}`、
/// 2026-09-05追加)。[CalendarEventRsvp]と同じくドキュメントIDを本人のuidに
/// し、firestore.rulesで「本人のuidのものにしか書き込めない」を単純な
/// 条件で表現する。
class ScheduleCoordinationResponse {
  const ScheduleCoordinationResponse({
    required this.userId,
    required this.votes,
    this.respondedAt,
  });

  final String userId;

  /// [scheduleCoordinationCandidateKey] -> 回答。
  final Map<String, ScheduleCoordinationVote> votes;
  final Timestamp? respondedAt;

  factory ScheduleCoordinationResponse.fromJson(
    String userId,
    Map<String, dynamic> json,
  ) {
    final rawVotes = json['votes'] as Map? ?? const {};
    final votes = <String, ScheduleCoordinationVote>{};
    for (final entry in rawVotes.entries) {
      final vote = ScheduleCoordinationVote.fromName(entry.value as String?);
      if (vote != null) votes[entry.key as String] = vote;
    }
    return ScheduleCoordinationResponse(
      userId: userId,
      votes: votes,
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'votes': votes.map((key, vote) => MapEntry(key, vote.name)),
    'respondedAt': respondedAt ?? FieldValue.serverTimestamp(),
  };
}
