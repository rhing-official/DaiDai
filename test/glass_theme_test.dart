import 'package:daidai/theme/glass/glass_theme.dart';
import 'package:daidai/theme/glass/glass_theme_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accent = Color(0xFFF08300);

  test('ライト/ダークどちらもGlassThemeExtrasを含む', () {
    final light = GlassTheme.light(accent);
    final dark = GlassTheme.dark(accent);

    expect(light.extension<GlassThemeExtras>(), isNotNull);
    expect(dark.extension<GlassThemeExtras>(), isNotNull);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
  });

  test('背景色はアクセントカラーの色相に関わらず中立色に固定される', () {
    final theme = GlassTheme.light(accent);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF2F2F5));
  });

  test('cardバリアントはchrome/floatingよりぼかしが弱い前提のtintAlphaを持つ', () {
    final extras = GlassTheme.light(accent).extension<GlassThemeExtras>()!;
    expect(extras.cardTintAlpha, greaterThan(extras.chromeTintAlpha));
  });
}
