import 'package:daidai/features/calendar/calendar_chip.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/contact_alias_providers.dart';
import 'package:daidai/widgets/gekiga/gekiga_panel_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AppUiStyle style,
  required bool styled,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(style),
        myContactAliasesProvider.overrideWith(
          (ref) => Stream.value(const <String, String>{}),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CalendarResponseGroup(
            label: '未回答',
            users: const [
              AppUser(userId: 'u1', rhingSeed: 'alice'),
              AppUser(userId: 'u2', rhingSeed: 'bob'),
            ],
            conversationId: 'c',
            styledMemberChips: styled,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('既定は、どのスタイルでも標準のChip（予定・日程調整のダイアログ）', (tester) async {
    await _pump(tester, style: AppUiStyle.gekiga, styled: false);
    expect(find.byType(Chip), findsNWidgets(2));
    expect(find.byType(GekigaJointedTileList), findsNothing);
  });

  testWidgets('劇画では、メンバーをジグザグ枠の箱で出す（投票のダイアログ）', (tester) async {
    await _pump(tester, style: AppUiStyle.gekiga, styled: true);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(GekigaJointedTileList), findsNWidgets(2));
    expect(find.textContaining('alice'), findsOneWidget);
  });

  testWidgets('版画では、メンバーを太枠の箱で出し、フラットは標準のChipのまま', (tester) async {
    await _pump(tester, style: AppUiStyle.block, styled: true);
    expect(find.byType(Chip), findsNothing);
    expect(find.textContaining('bob'), findsOneWidget);
    await _pump(tester, style: AppUiStyle.flat, styled: true);
    expect(find.byType(Chip), findsNWidgets(2));
  });
}
