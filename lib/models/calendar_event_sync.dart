import 'package:cloud_firestore/cloud_firestore.dart';

/// [CalendarEvent]1件・住人1人ごとのGoogleカレンダー同期状態
/// (`.../calendarEvents/{eventId}/syncStates/{uid}`、2026-09-01追加)。
///
/// ドキュメントIDを本人のuidにすることで、firestore.rulesで
/// 「本人のuidのものにしか書き込めない」を`request.auth.uid == uid`という
/// 単純な条件で表現できる（他人のsyncStatesへの成りすまし書き込み防止）。
/// 予定本体（[CalendarEvent]）に同期状態をMapで埋め込まないのも同じ理由。
class CalendarEventSync {
  const CalendarEventSync({
    required this.uid,
    this.googleEventId,
    this.status = CalendarSyncStatus.pending,
    this.googleCalendarId = 'primary',
    this.syncedAt,
    this.lastError,
  });

  final String uid;

  /// Google Calendar側のイベントID。作成成功時に記録し、以後の
  /// 更新・削除で再利用する（二重作成を防ぐ）。
  final String? googleEventId;
  final CalendarSyncStatus status;
  final String googleCalendarId;
  final Timestamp? syncedAt;

  /// 失敗理由（デバッグ・ユーザー表示用の簡易文字列）。
  final String? lastError;

  factory CalendarEventSync.fromJson(String uid, Map<String, dynamic> json) {
    return CalendarEventSync(
      uid: uid,
      googleEventId: json['googleEventId'] as String?,
      status: CalendarSyncStatus.fromName(json['status'] as String?),
      googleCalendarId: json['googleCalendarId'] as String? ?? 'primary',
      syncedAt: json['syncedAt'] as Timestamp?,
      lastError: json['lastError'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'googleEventId': googleEventId,
    'status': status.name,
    'googleCalendarId': googleCalendarId,
    'syncedAt': syncedAt,
    'lastError': lastError,
  };
}

enum CalendarSyncStatus {
  /// 未連携（オプトインしていない住人）。同期を試みない。
  skipped,

  /// 未反映。次回ワーカーが同期を試みる。
  pending,

  /// 同期処理中（他端末との二重登録防止用の一時状態、`pending`から遷移）。
  syncing,

  /// Google側に反映済み。
  synced,

  /// 同期に失敗した（再連携が必要、等）。
  failed,

  /// 予定が削除され、Google側からも削除する必要がある。
  pendingDelete,

  /// 削除処理中（他端末との二重削除防止用の一時状態、`pendingDelete`から遷移）。
  deleting;

  static CalendarSyncStatus fromName(String? name) {
    return CalendarSyncStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => CalendarSyncStatus.pending,
    );
  }
}
