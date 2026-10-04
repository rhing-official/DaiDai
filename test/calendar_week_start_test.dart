import 'package:daidai/models/calendar_week_start.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group('leadingBlanks', () {
    // 2026-10-01は木曜日。日曜始まりなら4マス、月曜始まりなら3マス。
    final thursday = DateTime(2026, 10);

    test('日曜始まり: 日曜=0、月曜=1、…、土曜=6', () {
      // 2026-02-01=日曜、2026-06-01=月曜、2026-08-01=土曜。
      expect(CalendarWeekStart.sunday.leadingBlanks(DateTime(2026, 2)), 0);
      expect(CalendarWeekStart.sunday.leadingBlanks(DateTime(2026, 6)), 1);
      expect(CalendarWeekStart.sunday.leadingBlanks(thursday), 4);
      expect(CalendarWeekStart.sunday.leadingBlanks(DateTime(2026, 8)), 6);
    });

    test('月曜始まり: 月曜=0、火曜=1、…、日曜=6', () {
      expect(CalendarWeekStart.monday.leadingBlanks(DateTime(2026, 6)), 0);
      expect(CalendarWeekStart.monday.leadingBlanks(thursday), 3);
      expect(CalendarWeekStart.monday.leadingBlanks(DateTime(2026, 8)), 5);
      expect(CalendarWeekStart.monday.leadingBlanks(DateTime(2026, 2)), 6);
    });

    test('どの月でも先頭余白は0〜6で、余白分戻ると週の先頭の曜日になる', () {
      for (final start in CalendarWeekStart.values) {
        final firstWeekday = start == CalendarWeekStart.sunday
            ? DateTime.sunday
            : DateTime.monday;
        for (var m = 1; m <= 12; m++) {
          final first = DateTime(2026, m);
          final blanks = start.leadingBlanks(first);
          expect(blanks, inInclusiveRange(0, 6));
          expect(first.subtract(Duration(days: blanks)).weekday, firstWeekday);
        }
      }
    });
  });

  test('曜日ラベルは週の先頭の曜日から並ぶ', () {
    String label(CalendarWeekStart s, int i) =>
        DateFormat.E('en').format(s.weekdayLabelAnchor.add(Duration(days: i)));
    expect(
      [for (var i = 0; i < 7; i++) label(CalendarWeekStart.sunday, i)],
      ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    );
    expect(
      [for (var i = 0; i < 7; i++) label(CalendarWeekStart.monday, i)],
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    );
  });

  test('保存値が無い・不明なら日曜始まり（従来どおり）', () {
    expect(CalendarWeekStart.fromName(null), CalendarWeekStart.sunday);
    expect(CalendarWeekStart.fromName('xxx'), CalendarWeekStart.sunday);
    expect(CalendarWeekStart.fromName('monday'), CalendarWeekStart.monday);
  });
}
