import 'package:daidai/l10n/holiday_data.dart';
import 'package:daidai/l10n/observances.dart';
import 'package:daidai/l10n/religious_holidays.dart';
import 'package:daidai/providers/holiday_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('イースター', () {
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
  });

  test('祭日の固定日と母の日・父の日', () {
    expect(observancesOn(DateTime(2026, 11, 15)).single.id, 'shichigosan');
    expect(observancesOn(DateTime(2026, 5, 10)).single.id, 'mothersDay');
    expect(observancesOn(DateTime(2026, 6, 21)).single.id, 'fathersDay');
    expect(observancesOn(DateTime(2026, 11, 14)), isEmpty);
  });

  test('キリスト教と仏教', () {
    final christian = {kReligionChristian};
    String? id(DateTime d, Set<String> r) {
      final list = religiousHolidaysOn(d, r);
      return list.isEmpty ? null : list.first.id;
    }

    expect(id(DateTime(2026, 4, 5), christian), 'easter');
    expect(id(DateTime(2026, 2, 18), christian), 'ashWednesday');
    expect(id(DateTime(2026, 4, 3), christian), 'goodFriday');
    expect(id(DateTime(2026, 4, 5), {kReligionBuddhist}), isNull);
    expect(id(DateTime(2026, 4, 8), {kReligionBuddhist}), 'hanamatsuri');
  });

  test('設定で出し分ける', () {
    const off = HolidaySettings(observances: false);
    expect(holidaysFor(DateTime(2026, 11, 15), off, 'JP'), isEmpty);
    final both = holidaysFor(
      DateTime(2026, 12, 25),
      const HolidaySettings(religions: {kReligionChristian}),
      'JP',
    );
    expect(both.map((e) => e.kind), [HolidayKind.observance]);
    // 地域が日本以外なら日本の祝日は出ない。
    expect(
      holidaysFor(DateTime(2026, 11, 23), const HolidaySettings(), 'US'),
      isEmpty,
    );
    expect(
      holidaysFor(
        DateTime(2026, 11, 23),
        const HolidaySettings(),
        'JP',
      ).single.kind,
      HolidayKind.public,
    );
  });
}
