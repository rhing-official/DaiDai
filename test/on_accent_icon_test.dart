import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/appearance_colors_provider.dart';
import 'package:daidai/theme/app_theme.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/theme/chalk/chalk_theme.dart';
import 'package:daidai/theme/kinari/kinari_theme.dart';
import 'package:daidai/widgets/nav_chip.dart';

/// 再発防止（2026-11-27）。明るい背景で、アクセントで塗った選択中のメニューチップのアイコンが、
/// 白ではなくクリーム色になる不具合が、デザインごとに繰り返し出た。原因は、標準のアクセント上の色
/// （#EFEFF1）が、明るい背景で白く見えなかったこと。標準の色は純白に固定し、どのデザインでも、
/// 選択中のアイコンがテーマの`onPrimary`（＝設定のアクセント上の色）になることを検査する。
void main() {
  const accent = Color(0xFF3D2EE0);
  const white = Color(0xFFFFFFFF);

  test('明るい背景（胡粉）の、アクセント上の標準の色は純白', () {
    expect(
      AppearanceSlot.light.defaultFor(AppearanceColorKind.onAccent),
      white,
    );
    expect(kDefaultOnAccentColorLight, white);
  });

  final themes = <AppUiStyle, ThemeData>{
    AppUiStyle.flat: AppTheme.light(accent, onAccentColor: white),
    AppUiStyle.block: BlockTheme.light(accent, onAccentColor: white),
    AppUiStyle.chalk: ChalkTheme.build(
      accent,
      null,
      background: const Color(0xFFFFFFFF),
      onAccentColor: white,
    ),
    AppUiStyle.kinari: KinariTheme.build(accent, null, onAccentColor: white),
  };

  for (final entry in themes.entries) {
    testWidgets('${entry.key.name}: 選択中のアイコンは、アクセント上の色（onPrimary）', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(entry.key),
            initialAccentColorProvider.overrideWithValue(accent),
          ],
          child: MaterialApp(
            theme: entry.value,
            home: Scaffold(
              body: Center(
                child: NavChip(
                  icon: Icons.search,
                  iconSize: 24,
                  label: '検索',
                  selected: true,
                  popped: false,
                  vertical: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, entry.value.colorScheme.onPrimary);
      expect(icon.color, white);
    });
  }
}
