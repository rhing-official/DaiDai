import 'package:daidai/features/calendar/date_time_pick.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/calendar_week_start.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/calendar_system_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ja'));
  testWidgets('範囲外の時刻で「OK」を押しても時刻ピッカーは閉じず、案内だけ出る', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var invalidCount = 0;
    DateTime? result;
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          effectiveWeekStartProvider.overrideWith(
            (ref, id) => CalendarWeekStart.sunday,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickDateAndTime(
                  context,
                  conversationId: 'c',
                  initial: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 30)),
                  // 常に範囲外にして、閉じないことを確かめる。
                  isValid: (_) => false,
                  onInvalid: () => invalidCount++,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 日付ダイアログ → 完了
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
    // 時刻ピッカーが出ている。
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(invalidCount, 1);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    // キャンセルすると閉じてnull。
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(result, isNull);
  });
}
