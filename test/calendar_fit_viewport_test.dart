import 'package:daidai/features/calendar/calendar_pane_view.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/calendar_category.dart';
import 'package:daidai/models/calendar_event.dart';
import 'package:daidai/models/calendar_week_start.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/calendar_week_start_provider.dart';
import 'package:daidai/models/schedule_coordination.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/calendar_category_repository.dart';
import 'package:daidai/repositories/calendar_event_repository.dart';
import 'package:daidai/repositories/schedule_coordination_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeEvents implements CalendarEventRepository {
  @override
  Stream<List<CalendarEvent>> watchEvents({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoordinations implements ScheduleCoordinationRepository {
  @override
  Stream<List<ScheduleCoordination>> watchCoordinations({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategories implements CalendarCategoryRepository {
  @override
  Stream<List<CalendarCategory>> watchCategories({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<int> _pump(WidgetTester tester, Size size, VoidCallback onClose) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarEventRepositoryProvider.overrideWithValue(_FakeEvents()),
        scheduleCoordinationRepositoryProvider.overrideWithValue(
          _FakeCoordinations(),
        ),
        calendarCategoryRepositoryProvider.overrideWithValue(_FakeCategories()),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialAccentColorProvider.overrideWithValue(kDefaultAccentColor),
        initialCalendarWeekStartProvider.overrideWithValue(
          CalendarWeekStart.sunday,
        ),
      ],
      child: MaterialApp(
        home: CalendarPaneView(
          isDm: true,
          conversationId: 'dm1',
          roomId: 'room1',
          currentUser: AppUser(userId: 'u1', rhingSeed: 'seed'),
          onClose: onClose,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return 0;
}

void main() {
  setUpAll(() => initializeDateFormatting('ja'));

  for (final size in const [Size(360, 640), Size(400, 800), Size(1200, 800)]) {
    testWidgets(
      '${size.width.toInt()}x${size.height.toInt()}: 月全体がスクロール無しで収まる',
      (tester) async {
        await _pump(tester, size, () {});
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scrollable.position.maxScrollExtent, 0);
      },
    );
  }

  testWidgets('スクロール不要なので下スワイプで閉じられる', (tester) async {
    var closed = 0;
    await _pump(tester, const Size(360, 640), () => closed++);
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 300),
      1500,
    );
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('月送りはスライドで切り替わり、途中でも例外・スクロールが出ない', (tester) async {
    await _pump(tester, const Size(360, 640), () {});
    String monthText() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => RegExp(r'^\d{4}年\d{1,2}月$').hasMatch(t));
    final before = monthText();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    // スライドの途中: 前の月と新しい月の両方が描画されている。
    expect(find.byType(InkWell).evaluate().length, greaterThan(28));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(monthText(), isNot(before));
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
  });
}
