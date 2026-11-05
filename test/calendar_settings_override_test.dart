import 'package:daidai/models/calendar_system.dart';
import 'package:daidai/models/calendar_week_start.dart';
import 'package:daidai/models/conversation_prefs.dart';
import 'package:daidai/providers/calendar_system_provider.dart';
import 'package:daidai/providers/calendar_week_start_provider.dart';
import 'package:daidai/providers/holiday_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer container({
    CalendarWeekStart? weekOverride,
    CalendarSystem? systemOverride,
    HolidaySettings? holidayOverride,
  }) {
    return ProviderContainer(
      overrides: [
        initialCalendarWeekStartProvider.overrideWithValue(
          CalendarWeekStart.monday,
        ),
        initialCalendarSystemProvider.overrideWithValue(
          CalendarSystem.japanese,
        ),
        initialHolidaySettingsProvider.overrideWithValue(
          const HolidaySettings(observances: false),
        ),
        conversationWeekStartProvider.overrideWith((ref, id) => weekOverride),
        conversationCalendarSystemProvider.overrideWith(
          (ref, id) => systemOverride,
        ),
        conversationHolidayOverrideProvider.overrideWith(
          (ref, id) => holidayOverride,
        ),
      ],
    );
  }

  test('上書きが無ければ標準に従う', () {
    final c = container();
    addTearDown(c.dispose);
    expect(c.read(effectiveWeekStartProvider('c1')), CalendarWeekStart.monday);
    expect(
      c.read(effectiveCalendarSystemProvider('c1')),
      CalendarSystem.japanese,
    );
    expect(c.read(effectiveHolidaySettingsProvider('c1')).observances, isFalse);
  });

  test('語らいの上書きは標準より優先される', () {
    final c = container(
      weekOverride: CalendarWeekStart.sunday,
      systemOverride: CalendarSystem.gregorian,
      holidayOverride: const HolidaySettings(observances: true),
    );
    addTearDown(c.dispose);
    expect(c.read(effectiveWeekStartProvider('c1')), CalendarWeekStart.sunday);
    expect(
      c.read(effectiveCalendarSystemProvider('c1')),
      CalendarSystem.gregorian,
    );
    expect(c.read(effectiveHolidaySettingsProvider('c1')).observances, isTrue);
  });

  test('標準を変えると、上書きしていない語らいに反映される', () async {
    final c = container();
    addTearDown(c.dispose);
    await c
        .read(calendarWeekStartProvider.notifier)
        .setWeekStart(CalendarWeekStart.sunday)
        .catchError((_) {});
    expect(c.read(effectiveWeekStartProvider('c1')), CalendarWeekStart.sunday);
  });

  test('祝日の上書きの保存形式', () {
    const settings = HolidaySettings(
      regions: {'JP'},
      observances: false,
      religions: {'christian'},
    );
    final restored = HolidaySettings.fromOverrideJson(
      settings.toOverrideJson(),
    );
    expect(restored.regions, {'JP'});
    expect(restored.observances, isFalse);
    expect(restored.religions, {'christian'});
    // 地域が居住国に従う場合はregionsを書かない。
    expect(
      const HolidaySettings().toOverrideJson().containsKey('regions'),
      isFalse,
    );
  });

  test('ConversationPrefsが新しい項目を読み書きする', () {
    final prefs = ConversationPrefs.fromJson({
      'calendarWeekStart': 'monday',
      'holidayOverride': {
        'observances': true,
        'religions': ['buddhist'],
      },
    });
    expect(prefs.calendarWeekStart, 'monday');
    expect(prefs.holidayOverride!['observances'], isTrue);
    expect(prefs.toJson()['calendarWeekStart'], 'monday');
  });
}
