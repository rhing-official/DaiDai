import 'package:cloud_firestore/cloud_firestore.dart';

/// 予定の出欠回答（参加/不参加/遅刻）を表す3択（2026-09-02追加）。
enum CalendarRsvpStatus {
  attending,
  notAttending,
  late_,
  undecided;

  static CalendarRsvpStatus? fromName(String? name) {
    for (final status in CalendarRsvpStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }
}

/// [CalendarEvent]1件・住人1人ごとの出欠回答
/// (`.../calendarEvents/{eventId}/rsvps/{uid}`、2026-09-02追加)。
///
/// `CalendarEventSync`と同じくドキュメントIDを本人のuidにし、firestore.rules
/// で「本人のuidのものにしか書き込めない」を単純な条件で表現する。
/// 複数日にまたがる予定は[dayStatuses]で日ごとに出欠を持つ（途中参加を
/// 考慮するため）。備考は日ごとではなく回答全体で1つ（2026-09-02決定）。
class CalendarEventRsvp {
  const CalendarEventRsvp({
    required this.userId,
    required this.dayStatuses,
    this.note,
    this.respondedAt,
  });

  final String userId;

  /// 'yyyy-MM-dd'（[calendarEventDayKey]参照） -> 出欠。
  final Map<String, CalendarRsvpStatus> dayStatuses;
  final String? note;
  final Timestamp? respondedAt;

  factory CalendarEventRsvp.fromJson(String userId, Map<String, dynamic> json) {
    final rawDayStatuses = json['dayStatuses'] as Map? ?? const {};
    final dayStatuses = <String, CalendarRsvpStatus>{};
    for (final entry in rawDayStatuses.entries) {
      final status = CalendarRsvpStatus.fromName(entry.value as String?);
      if (status != null) dayStatuses[entry.key as String] = status;
    }
    return CalendarEventRsvp(
      userId: userId,
      dayStatuses: dayStatuses,
      note: json['note'] as String?,
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'dayStatuses': dayStatuses.map((day, status) => MapEntry(day, status.name)),
    'note': note,
    'respondedAt': respondedAt ?? FieldValue.serverTimestamp(),
  };
}
