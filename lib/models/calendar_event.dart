import 'package:cloud_firestore/cloud_firestore.dart';

/// 寄合単位の共有予定（`directMessages/{dmId}/rooms/{roomId}/calendarEvents/{eventId}`
/// または`groups/{groupId}/rooms/{roomId}/calendarEvents/{eventId}`、2026-09-01追加）。
///
/// その寄合の参加者全員が対等に作成できる共有カレンダーの予定本体。
/// 作成後の内容編集は行わない（出欠回答済みの住人との齟齬を避けるため、
/// 2026-09-02方針）。削除のみ[createdBy]本人に限り可能（firestore.rules参照）。
/// Googleカレンダーへの同期状態は個人ごとに異なるためこのドキュメントには
/// 含めず、[CalendarEventSync]（`syncStates`サブコレクション）に分離している。
/// 出欠回答は[CalendarEventRsvp]（`rsvps`サブコレクション）に分離している。
class CalendarEvent {
  const CalendarEvent({
    required this.eventId,
    required this.roomId,
    required this.title,
    this.description,
    required this.startAt,
    this.endAt,
    this.isAllDay = false,
    this.location,
    required this.createdBy,
    this.createdAt,
    this.syncedCount = 0,
    this.rsvpEnabled = true,
    this.rsvpPerDay = true,
    this.rsvpCount = 0,
    this.rsvpDeadline,
  });

  final String eventId;
  final String roomId;
  final String title;
  final String? description;
  final Timestamp startAt;

  /// 終了未定の予定も許容するためnullable。
  final Timestamp? endAt;
  final bool isAllDay;
  final String? location;
  final String createdBy;
  final Timestamp? createdAt;

  /// 一覧表示用の非正規化カウンタ（「n人に反映済み」表示用）。
  /// [CalendarEventSync]がsyncedになるたびにRepositoryがバッチ更新する。
  final int syncedCount;

  /// 出欠確認を行うか（2026-09-02追加、作成時にのみ選べる）。デフォルト
  /// `true`は、この機能追加前に作られた既存予定でも出欠確認ありの従来動作を
  /// 維持するため。
  final bool rsvpEnabled;

  /// 複数日にまたがる予定で、日ごとに出欠を確認するか（2026-09-02追加）。
  /// 単日の予定・[rsvpEnabled]がfalseの予定では意味を持たない。デフォルト
  /// `true`は、既存の複数日予定で従来の「日ごと確認」動作を維持するため。
  final bool rsvpPerDay;

  /// 出欠回答をした住人の人数（非正規化カウンタ、2026-09-04追加）。
  /// `FirestoreCalendarEventRepository.setRsvp`が、ある住人の`rsvps/{uid}`が
  /// 新規作成された時だけ+1する（既存回答の更新では増やさない）。この値が
  /// 0の間だけ、作成者は予定の内容を編集できる（firestore.rules参照）。
  final int rsvpCount;

  /// 回答期限（2026-09-04追加）。nullなら期限なし。過ぎても未回答者への
  /// 自動措置は行わない（未回答のまま）が、新規回答・既存回答の変更は
  /// firestore.rulesで拒否される（`calendar_event_detail_dialog.dart`が
  /// クライアント側でもUI無効化する）。
  final Timestamp? rsvpDeadline;

  factory CalendarEvent.fromJson(String eventId, Map<String, dynamic> json) {
    return CalendarEvent(
      eventId: eventId,
      roomId: json['roomId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startAt: json['startAt'] as Timestamp,
      endAt: json['endAt'] as Timestamp?,
      isAllDay: json['isAllDay'] as bool? ?? false,
      location: json['location'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as Timestamp?,
      syncedCount: json['syncedCount'] as int? ?? 0,
      rsvpEnabled: json['rsvpEnabled'] as bool? ?? true,
      rsvpPerDay: json['rsvpPerDay'] as bool? ?? true,
      rsvpCount: json['rsvpCount'] as int? ?? 0,
      rsvpDeadline: json['rsvpDeadline'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'title': title,
    'description': description,
    'startAt': startAt,
    'endAt': endAt,
    'isAllDay': isAllDay,
    'location': location,
    'createdBy': createdBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'syncedCount': syncedCount,
    'rsvpEnabled': rsvpEnabled,
    'rsvpPerDay': rsvpPerDay,
    'rsvpCount': rsvpCount,
    'rsvpDeadline': rsvpDeadline,
  };
}

/// [CalendarEvent.rsvpEnabled]がtrueかつ[CalendarEvent.rsvpPerDay]がfalseの
/// 予定（単日、または複数日でも日ごと確認をしない予定）で、
/// [CalendarEventRsvp.dayStatuses]の唯一のキーとして使う固定値
/// （実際の日付文字列'yyyy-MM-dd'とは衝突しない、2026-09-02追加）。
const calendarRsvpSingleKey = 'all';

/// [event]が及ぶ暦日を1日単位で列挙する（`startAt`の日付から`endAt`の日付まで、
/// `endAt`が無ければ`startAt`の1日のみ）。出欠を日ごとに取る機能
/// （[CalendarEventRsvp]）で、複数日にまたがる予定の対象日一覧を得るために使う
/// （2026-09-02追加）。
List<DateTime> calendarEventDates(CalendarEvent event) {
  DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
  final start = dateOnly(event.startAt.toDate());
  final end = event.endAt != null ? dateOnly(event.endAt!.toDate()) : start;
  final days = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

/// [CalendarEventRsvp.dayStatuses]のキー形式（'yyyy-MM-dd'）に変換する。
String calendarEventDayKey(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}
