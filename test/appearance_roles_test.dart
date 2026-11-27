import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/dark_variant.dart';
import 'package:daidai/theme/app_theme.dart';
import 'package:daidai/theme/appearance_roles.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/theme/chalk/chalk_theme.dart';
import 'package:daidai/theme/glass/glass_theme.dart';
import 'package:daidai/theme/kinari/kinari_theme.dart';

void main() {
  const accent = Color(0xFF3D2EE0);
  const custom = Color(0xFF808080);

  AppearancePalette? rolesOf(dynamic theme) =>
      (theme.extension<AppearanceRoles>() as AppearanceRoles?)?.palette;

  test('全てのスタイルのテーマが、色の役割を持つ', () {
    expect(rolesOf(AppTheme.light(accent)), isNotNull);
    expect(rolesOf(AppTheme.dark(accent)), isNotNull);
    expect(rolesOf(GlassTheme.light(accent)), isNotNull);
    expect(rolesOf(GlassTheme.dark(accent)), isNotNull);
    expect(rolesOf(BlockTheme.light(accent)), isNotNull);
    expect(rolesOf(BlockTheme.dark(accent)), isNotNull);
    expect(rolesOf(ChalkTheme.build(accent, null)), isNotNull);
    expect(rolesOf(KinariTheme.build(accent, null)), isNotNull);
  });

  test('背景色を指定すると、役割の背景は、帯に収めた色になる', () {
    final palette = AppearancePalette.fromBackground(custom);
    for (final theme in [
      AppTheme.light(accent, palette: palette),
      GlassTheme.light(accent, palette: palette),
      BlockTheme.light(accent, palette: palette),
    ]) {
      expect(rolesOf(theme)!.background, palette.background);
    }
  });

  test('選択の塗りと下地は、背景から作る', () {
    final p = AppearancePalette.fromBackground(const Color(0xFFF2F2F5));
    final fill = p.selectionFill(accent, alpha: 0.45);
    expect(fill.a, 1.0);
    expect(fill, isNot(p.background));
    expect(p.listBase(glass: false), p.background);
    expect(p.listBase(glass: true), isNot(p.background));
  });
}
