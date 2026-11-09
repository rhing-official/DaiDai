import 'package:daidai/features/chat/talks_header_metrics.dart';
import 'package:daidai/features/chat/talks_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/gekiga/gekiga_panel_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 語らい一覧・寄合一覧の見出しの部品（トグル・ボタン・会話名の箱）が、全UIスタイルで
/// トグルと同じ高さになること（2026-11-09）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final style in AppUiStyle.values) {
    testWidgets('見出しの部品の高さがトグルと一致する（$style）', (tester) async {
      Widget tab() => CategoryTab(
        label: '一対',
        count: 8,
        selected: false,
        onTap: () {},
        slidable: false,
      );
      late double expected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAccentColorProvider.overrideWithValue(
              const Color(0xFF3D2EE0),
            ),
            initialAccentColorsByStyleProvider.overrideWithValue(const {}),
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
            initialAppUiStyleProvider.overrideWithValue(style),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  expected = talksControlHeight(context, style);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        style == AppUiStyle.gekiga
                            ? GekigaJointedPair(
                                leftSeed: 1,
                                leftSelected: false,
                                left: tab(),
                                rightSeed: 2,
                                rightSelected: false,
                                right: tab(),
                              )
                            : KeyedSubtree(key: const Key('tab'), child: tab()),
                        TalksControlButton(
                          key: const Key('button'),
                          icon: Icons.add,
                          onPressed: () {},
                        ),
                        const TalksNameChip(key: Key('chip'), label: '終焉と消失'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final tabHeight = style == AppUiStyle.gekiga
          ? tester.getSize(find.byType(GekigaJointedPair)).height
          : tester.getSize(find.byKey(const Key('tab'))).height;
      expect(tabHeight, closeTo(expected, 0.5), reason: 'トグル自身が基準と一致する');
      expect(
        tester.getSize(find.byKey(const Key('button'))).height,
        closeTo(tabHeight, 0.5),
        reason: 'ボタン',
      );
      expect(
        tester.getSize(find.byKey(const Key('chip'))).height,
        closeTo(tabHeight, 0.5),
        reason: '会話名の箱',
      );
    });
  }
}
