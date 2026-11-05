import 'package:daidai/features/calendar/holiday_detail_dialog.dart';
import 'package:daidai/l10n/holiday_data.dart';
import 'package:daidai/models/calendar_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ja'));

  testWidgets('祝日のポップアップに名称・種類・日付が出る（画像が無くても落ちない）', (tester) async {
    const entry = HolidayEntry(
      HolidayKind.public,
      'newYear',
      '元日',
      'New Year',
      'Jour de l’An',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHolidayDetailDialog(
              context,
              entry: entry,
              day: DateTime(2027, 1, 1),
              calendarSystem: CalendarSystem.japanese,
              localeCode: 'ja',
              kindLabel: '祝日',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('元日'), findsOneWidget);
    expect(find.text('祝日'), findsOneWidget);
    expect(find.textContaining('令和9年'), findsOneWidget);
    expect(holidayImagePath(entry), 'assets/holidays/public_newYear.webp');
  });
}
