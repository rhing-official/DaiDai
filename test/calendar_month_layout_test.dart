import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/calendar/calendar_month_layout.dart';
import 'package:daidai/models/calendar_event.dart';
import 'package:daidai/models/schedule_coordination.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _event(String title, DateTime start, {DateTime? end}) {
  return CalendarEvent(
    eventId: title,
    roomId: 'room1',
    title: title,
    startAt: Timestamp.fromDate(start),
    endAt: end != null ? Timestamp.fromDate(end) : null,
    isAllDay: true,
    createdBy: 'user1',
  );
}

ScheduleCoordination _coordination(String title, List<DateTime> dates) {
  return ScheduleCoordination(
    coordinationId: title,
    roomId: 'room1',
    title: title,
    candidateDates: dates.map(Timestamp.fromDate).toList(),
    createdBy: 'user1',
  );
}

List<DateTime> _week(DateTime sunday) => [
  for (var i = 0; i < 7; i++) sunday.add(Duration(days: i)),
];

void main() {
  group('buildMonthItems', () {
    test('予定は1件がそのまま1つのCalendarMonthItemになる', () {
      final items = buildMonthItems(
        [_event('会議', DateTime(2026, 9, 1), end: DateTime(2026, 9, 3))],
        [],
        {},
      );
      expect(items, hasLength(1));
      expect(items.single.startDate, DateTime(2026, 9, 1));
      expect(items.single.endDate, DateTime(2026, 9, 3));
      expect(items.single.isCoordination, isFalse);
    });

    test('日程調整の連続しない候補日は複数のCalendarMonthItemに分割される', () {
      final items = buildMonthItems([], [
        _coordination('忘年会', [
          DateTime(2026, 9, 11),
          DateTime(2026, 9, 12),
          DateTime(2026, 9, 13),
          DateTime(2026, 9, 20),
        ]),
      ], {});
      expect(items, hasLength(2));
      expect(items[0].startDate, DateTime(2026, 9, 11));
      expect(items[0].endDate, DateTime(2026, 9, 13));
      expect(items[1].startDate, DateTime(2026, 9, 20));
      expect(items[1].endDate, DateTime(2026, 9, 20));
      expect(items.every((item) => item.isCoordination), isTrue);
    });
  });

  group('computeWeekLaneLayout', () {
    test('単日予定が複数並ぶ通常ケースでは別々のレーンに割り当たる', () {
      final sunday = DateTime(2026, 8, 30); // 2026-08-30は日曜
      final week = _week(sunday);
      final items = buildMonthItems(
        [
          _event('予定A', DateTime(2026, 9, 1)),
          _event('予定B', DateTime(2026, 9, 1)),
        ],
        [],
        {},
      );

      final layout = computeWeekLaneLayout(week, items, 3);
      expect(layout.segments, hasLength(2));
      final lanes = layout.segments.map((s) => s.lane).toSet();
      expect(lanes, {0, 1});
    });

    test('週をまたぐ複数日予定は2つのセグメントに分かれ、同じレーンに割り当たる', () {
      // 2026-09-02(水)始まり〜2026-09-08(水)終わり、9/6(日)を週境界とする。
      final start = DateTime(2026, 9, 2);
      final end = DateTime(2026, 9, 8);
      final items = buildMonthItems([_event('連休', start, end: end)], [], {});

      final week1Sunday = DateTime(2026, 8, 30);
      final week2Sunday = DateTime(2026, 9, 6);
      final week1 = _week(week1Sunday);
      final week2 = _week(week2Sunday);

      final layout1 = computeWeekLaneLayout(week1, items, 3);
      final layout2 = computeWeekLaneLayout(week2, items, 3);

      expect(layout1.segments, hasLength(1));
      expect(layout2.segments, hasLength(1));

      final segment1 = layout1.segments.single;
      final segment2 = layout2.segments.single;

      // 週1: 水(9/2)始まり、週末(土=9/5)まで続く。
      expect(segment1.startCol, start.difference(week1Sunday).inDays);
      expect(segment1.endCol, 6);

      // 週2: 日曜(9/6)始まりで継続、火(9/8)で本当に終わる。
      expect(segment2.startCol, 0);
      expect(segment2.endCol, end.difference(week2Sunday).inDays);

      expect(segment1.lane, segment2.lane);
    });

    test('レーン数がmaxLanesを超えた場合、日ごとの非表示件数が正しく集計される', () {
      final sunday = DateTime(2026, 8, 30);
      final week = _week(sunday);
      final items = buildMonthItems(
        [
          _event('予定A', DateTime(2026, 9, 1)),
          _event('予定B', DateTime(2026, 9, 1)),
          _event('予定C', DateTime(2026, 9, 1)),
        ],
        [],
        {},
      );

      final layout = computeWeekLaneLayout(week, items, 2);
      // 3件のうち2件のみレーン0・1に収まり、残り1件が非表示になる。
      expect(layout.segments, hasLength(2));

      final tuesday = DateTime(2026, 9, 1);
      expect(layout.overflowCountByDay[tuesday], 1);
      final otherDay = DateTime(2026, 8, 31);
      expect(layout.overflowCountByDay[otherDay], 0);
    });

    test('週をまたいで継続する非表示セグメントは、週内で重なる全ての日に計上される', () {
      final sunday = DateTime(2026, 8, 30);
      final week = _week(sunday);
      final items = buildMonthItems(
        [
          _event('予定A', DateTime(2026, 9, 1)),
          _event('予定B', DateTime(2026, 9, 1)),
          _event('予定C（複数日）', DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
        ],
        [],
        {},
      );

      // maxLanesを1にして、開始日が同じ中で最も長い予定Cだけが表示され、
      // 単日の予定A・予定Bが非表示になるケースを検証する。
      final layout = computeWeekLaneLayout(week, items, 1);
      expect(layout.segments, hasLength(1));
      expect(layout.segments.single.item.title, '予定C（複数日）');

      final tuesday = DateTime(2026, 9, 1);
      expect(layout.overflowCountByDay[tuesday], 2);
    });
  });
}
