import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/widgets/profile_card_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = ProfileCard(id: 'a', name: '新');
const _b = ProfileCard(id: 'b', name: '旧');

void main() {
  Future<List<String?>> pump(
    WidgetTester tester, {
    required ProfileCard? active,
    String? selected,
    AppUiStyle style = AppUiStyle.flat,
  }) async {
    final picked = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(style),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ProfileCardPicker(
                strings: ref.watch(appStringsProvider),
                cards: const [_a, _b],
                selectedCardId: selected,
                activeCard: active,
                onSelected: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('標準のカードは「新（標準）」の1行だけで、同名の行は出ない', (tester) async {
    await pump(tester, active: _a);
    expect(find.text('新（標準）'), findsOneWidget);
    expect(find.text('新'), findsNothing);
    expect(find.text('旧'), findsOneWidget);
    expect(find.text('標準（新）'), findsNothing);
  });

  testWidgets('標準の行を選ぶとnull（標準に追従）が返る', (tester) async {
    final picked = await pump(tester, active: _a, selected: 'b');
    await tester.tap(find.text('新（標準）'));
    expect(picked, [null]);
  });

  testWidgets('標準と同じカードを固定していた設定も標準の行が選択状態', (tester) async {
    await pump(tester, active: _a, selected: 'a');
    final radios = tester.widgetList<RadioListTile<String?>>(
      find.byType(RadioListTile<String?>),
    );
    final standard = radios.first;
    expect(standard.value, isNull);
    expect(
      tester
          .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
          .groupValue,
      isNull,
    );
  });

  testWidgets('標準が未設定なら「標準」の行＋全カード', (tester) async {
    await pump(tester, active: null);
    expect(find.text('標準'), findsOneWidget);
    expect(find.text('新'), findsOneWidget);
    expect(find.text('旧'), findsOneWidget);
  });

  testWidgets('劇画でも同じ並びになる', (tester) async {
    await pump(tester, active: _a, style: AppUiStyle.gekiga);
    expect(find.text('新（標準）'), findsOneWidget);
    expect(find.text('新'), findsNothing);
  });
}
