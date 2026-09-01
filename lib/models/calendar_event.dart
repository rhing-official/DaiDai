import 'package:cloud_firestore/cloud_firestore.dart';

/// 寄合単位の共有予定（`directMessages/{dmId}/rooms/{roomId}/calendarEvents/{eventId}`
/// または`groups/{groupId}/rooms/{roomId}/calendarEvents/{eventId}`、2026-09-01追加）。
///
/// その寄合の参加者全員が対等に作成・編集・削除できる共有カレンダーの
/// 予定本体。Googleカレンダーへの同期状態は個人ごとに異なるため
/// このドキュメントには含めず、[CalendarEventSync]（`syncStates`サブ
/// コレクション）に分離している。
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
    this.updatedBy,
    this.updatedAt,
    this.syncedCount = 0,
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

  /// 直近の編集者（作成者以外のメンバーも編集できるため記録）。
  final String? updatedBy;
  final Timestamp? updatedAt;

  /// 一覧表示用の非正規化カウンタ（「n人に反映済み」表示用）。
  /// [CalendarEventSync]がsyncedになるたびにRepositoryがバッチ更新する。
  final int syncedCount;

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
      updatedBy: json['updatedBy'] as String?,
      updatedAt: json['updatedAt'] as Timestamp?,
      syncedCount: json['syncedCount'] as int? ?? 0,
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
    'updatedBy': updatedBy,
    'updatedAt': updatedAt,
    'syncedCount': syncedCount,
  };
}
