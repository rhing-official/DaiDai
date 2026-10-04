import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/calendar_event.dart';
import '../models/calendar_event_rsvp.dart';
import '../models/calendar_event_sync.dart';
import '../repositories/calendar_event_repository.dart';
import 'google_calendar_sync_service.dart';

/// 出欠の回答に「参加」または「遅刻」が1日でも含まれるか（2026-10-04追加）。
/// Googleカレンダーへ同期する（＝参加扱い）かどうかの判定に使う。
bool isAttendingAny(Map<String, CalendarRsvpStatus> dayStatuses) {
  return dayStatuses.values.any(
    (s) => s == CalendarRsvpStatus.attending || s == CalendarRsvpStatus.late_,
  );
}

/// 出欠の「回答を保存」を押した時に、その住人自身のGoogleカレンダーへ予定を
/// 同期する（2026-10-04追加、ユーザー指示）。予定作成時に全員分を自動で
/// 同期待ちにする方式は廃止し、参加した人だけが同期される。
/// ボタン操作の中で呼ぶ前提のため、アクセストークンは呼び出し側がその場で
/// （ユーザー操作の有効期間内に）取得して渡す。
class CalendarRsvpSync {
  CalendarRsvpSync({
    required CalendarEventRepository repository,
    required GoogleCalendarSyncService syncService,
  }) : _repo = repository,
       _service = syncService;

  final CalendarEventRepository _repo;
  final GoogleCalendarSyncService _service;

  /// 同期を実行する。Google側の失敗は例外のまま投げる（同期状態は`failed`に
  /// 記録済み）。呼び出し側は出欠の保存自体は成功扱いにしてエラーだけ通知する。
  Future<void> syncOnRsvp({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required CalendarEvent event,
    required String uid,
    required String calendarId,
    required String accessToken,
    required Map<String, CalendarRsvpStatus> dayStatuses,
  }) async {
    final existing = await _repo.getSyncState(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: event.eventId,
      uid: uid,
    );
    final googleEventId = existing?.googleEventId;

    if (!isAttendingAny(dayStatuses)) {
      // 参加でなくなった: 同期済みならGoogleカレンダーからも外す。
      if (googleEventId == null) return;
      await _service.deleteGoogleEvent(
        accessToken: accessToken,
        calendarId: existing!.googleCalendarId,
        googleEventId: googleEventId,
      );
      await _repo.deleteSyncState(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        eventId: event.eventId,
        uid: uid,
      );
      return;
    }

    try {
      var created = false;
      String resultId;
      if (googleEventId == null) {
        resultId = await _service.createGoogleEvent(
          accessToken: accessToken,
          calendarId: calendarId,
          event: event,
        );
        created = true;
      } else {
        try {
          await _service.updateGoogleEvent(
            accessToken: accessToken,
            calendarId: calendarId,
            googleEventId: googleEventId,
            event: event,
          );
          resultId = googleEventId;
        } on GoogleCalendarEventNotFoundException {
          resultId = await _service.createGoogleEvent(
            accessToken: accessToken,
            calendarId: calendarId,
            event: event,
          );
          created = true;
        }
      }
      await _repo.writeSyncState(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        eventId: event.eventId,
        syncState: CalendarEventSync(
          uid: uid,
          googleEventId: resultId,
          googleCalendarId: calendarId,
          status: CalendarSyncStatus.synced,
          syncedAt: Timestamp.now(),
        ),
      );
      if (created && googleEventId == null) {
        await _repo.incrementSyncedCount(
          isDm: isDm,
          conversationId: conversationId,
          roomId: roomId,
          eventId: event.eventId,
        );
      }
    } catch (e) {
      await _repo.writeSyncState(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        eventId: event.eventId,
        syncState: CalendarEventSync(
          uid: uid,
          googleEventId: googleEventId,
          status: CalendarSyncStatus.failed,
          lastError: e.toString(),
        ),
      );
      rethrow;
    }
  }
}
