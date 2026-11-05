import 'package:daidai/models/calendar_system.dart';
import 'package:daidai/l10n/japan_holidays.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
    await initializeDateFormatting('en_GB');
  });

  JapanHoliday? h(int y, int m, int d) => japanHolidayOf(DateTime(y, m, d));

  test('2026年の祝日', () {
    expect(h(2026, 1, 1), JapanHoliday.newYear);
    expect(h(2026, 1, 12), JapanHoliday.comingOfAge);
    expect(h(2026, 2, 23), JapanHoliday.emperorBirthday);
    expect(h(2026, 3, 20), JapanHoliday.springEquinox);
    expect(h(2026, 5, 6), JapanHoliday.substitute); // 5/3が日曜
    expect(h(2026, 7, 20), JapanHoliday.marine);
    expect(h(2026, 9, 21), JapanHoliday.respectForAged);
    expect(h(2026, 9, 22), JapanHoliday.citizens);
    expect(h(2026, 9, 23), JapanHoliday.autumnEquinox);
    expect(h(2026, 10, 12), JapanHoliday.sports);
    expect(h(2026, 11, 23), JapanHoliday.laborThanksgiving);
    expect(h(2026, 11, 5), isNull);
  });

  test('特例の年と範囲外', () {
    expect(h(2020, 7, 24), JapanHoliday.sports);
    expect(h(2021, 8, 9), JapanHoliday.substitute);
    expect(h(2019, 5, 1), JapanHoliday.enthronement);
    expect(h(1999, 1, 1), isNull);
  });

  test('和暦の見出し', () {
    expect(
      formatMonthTitle(CalendarSystem.japanese, DateTime(2026, 11), 'ja'),
      '令和8年11月',
    );
    expect(
      formatMonthTitle(CalendarSystem.japanese, DateTime(2019, 5), 'ja'),
      '令和元年5月',
    );
    expect(
      formatMonthTitle(CalendarSystem.japanese, DateTime(2019, 4), 'ja'),
      '平成31年4月',
    );
    expect(
      formatMonthTitle(CalendarSystem.gregorian, DateTime(2026, 11), 'ja'),
      '2026年11月',
    );
  });
}
