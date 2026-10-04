import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/calendar/calendar_event_form_dialog.dart';
import 'package:daidai/models/calendar_event.dart';
import 'package:daidai/models/calendar_event_rsvp.dart';
import 'package:daidai/models/calendar_event_sync.dart';
import 'package:daidai/repositories/calendar_event_repository.dart';
import 'package:daidai/services/calendar_rsvp_sync.dart';
import 'package:daidai/services/google_calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeRepo implements CalendarEventRepository {
  CalendarEventSync? state;
  final writes = <CalendarEventSync>[];
  var deleted = false;

  @override
  Future<CalendarEventSync?> getSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  }) async => state;

  @override
  Future<void> writeSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required CalendarEventSync syncState,
  }) async {
    writes.add(syncState);
    state = syncState;
  }

  @override
  Future<void> deleteSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  }) async {
    deleted = true;
    state = null;
  }

  @override
  Future<void> incrementSyncedCount({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CalendarEvent _event() => CalendarEvent(
  eventId: 'e1',
  roomId: 'r',
  title: 't',
  startAt: Timestamp.fromDate(DateTime(2026, 10, 13, 10)),
  endAt: Timestamp.fromDate(DateTime(2026, 10, 13, 11)),
  isAllDay: false,
  createdBy: 'u',
  rsvpEnabled: true,
  rsvpPerDay: false,
);

void main() {
  test('参加扱いは参加・遅刻が1日でもあるか', () {
    expect(isAttendingAny({'a': CalendarRsvpStatus.attending}), isTrue);
    expect(isAttendingAny({'a': CalendarRsvpStatus.late_}), isTrue);
    expect(
      isAttendingAny({
        'a': CalendarRsvpStatus.notAttending,
        'b': CalendarRsvpStatus.undecided,
      }),
      isFalse,
    );
    expect(isAttendingAny(const {}), isFalse);
  });

  test('終了日時の既定値は開始の1時間後（終日は開始日）', () {
    final start = DateTime(2026, 10, 4, 15, 30);
    expect(defaultEventEnd(start, false), DateTime(2026, 10, 4, 16, 30));
    expect(defaultEventEnd(start, true), DateTime(2026, 10, 4));
  });

  group('CalendarRsvpSync', () {
    Future<(_FakeRepo, List<String>)> run({
      required CalendarEventSync? existing,
      required Map<String, CalendarRsvpStatus> statuses,
    }) async {
      final repo = _FakeRepo()..state = existing;
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'POST') {
          return http.Response(jsonEncode({'id': 'g1'}), 200);
        }
        return http.Response('{}', 200);
      });
      await CalendarRsvpSync(
        repository: repo,
        syncService: GoogleCalendarSyncService(client: client),
      ).syncOnRsvp(
        isDm: false,
        conversationId: 'g',
        roomId: 'r',
        event: _event(),
        uid: 'u',
        calendarId: 'cal',
        accessToken: 'tok',
        dayStatuses: statuses,
      );
      return (repo, calls);
    }

    test('参加を保存するとGoogleに作成し、synced状態を書く', () async {
      final (repo, calls) = await run(
        existing: null,
        statuses: {'single': CalendarRsvpStatus.attending},
      );
      expect(calls, ['POST /calendar/v3/calendars/cal/events']);
      expect(repo.state?.status, CalendarSyncStatus.synced);
      expect(repo.state?.googleEventId, 'g1');
    });

    test('同期済みなら更新（PUT）する', () async {
      final (repo, calls) = await run(
        existing: const CalendarEventSync(
          uid: 'u',
          googleEventId: 'g9',
          status: CalendarSyncStatus.synced,
          googleCalendarId: 'cal',
        ),
        statuses: {'single': CalendarRsvpStatus.late_},
      );
      expect(calls, ['PUT /calendar/v3/calendars/cal/events/g9']);
      expect(repo.state?.googleEventId, 'g9');
    });

    test('不参加へ変えると同期済みの予定をGoogleから削除する', () async {
      final (repo, calls) = await run(
        existing: const CalendarEventSync(
          uid: 'u',
          googleEventId: 'g9',
          status: CalendarSyncStatus.synced,
          googleCalendarId: 'cal',
        ),
        statuses: {'single': CalendarRsvpStatus.notAttending},
      );
      expect(calls, ['DELETE /calendar/v3/calendars/cal/events/g9']);
      expect(repo.deleted, isTrue);
    });

    test('参加しておらず未同期なら何もしない', () async {
      final (repo, calls) = await run(
        existing: null,
        statuses: {'single': CalendarRsvpStatus.undecided},
      );
      expect(calls, isEmpty);
      expect(repo.writes, isEmpty);
    });
  });
}
