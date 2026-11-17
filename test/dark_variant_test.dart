import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/dark_variant.dart';
import 'package:daidai/providers/on_accent_color_provider.dart';
import 'package:daidai/providers/text_color_provider.dart';
import 'package:daidai/theme/app_theme.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/theme/glass/glass_theme.dart';

void main() {
  const accent = Color(0xFFEE7800);

  test('標準は従来のダークと同じ値', () {
    final theme = AppTheme.dark(accent);
    expect(theme.colorScheme.surface, AppTheme.darkBackground);
    expect(theme.colorScheme.surfaceContainerHighest, AppTheme.darkSurface);
  });

  test('種類ごとにフラット・ガラス・版画の背景が変わる', () {
    for (final v in DarkVariant.values) {
      expect(
        AppTheme.dark(accent, variant: v).colorScheme.surface,
        v.background,
      );
      expect(
        GlassTheme.dark(accent, variant: v).colorScheme.surface,
        v.glassBackground,
      );
      expect(
        BlockTheme.dark(accent, variant: v).colorScheme.surface,
        v.background,
      );
    }
  });

  test('漆黒だけカードに枠線が付く', () {
    final black = AppTheme.dark(accent, variant: DarkVariant.black);
    final std = AppTheme.dark(accent);
    expect(
      (black.cardTheme.shape as RoundedRectangleBorder).side.color,
      DarkVariant.black.outline,
    );
    expect(
      (std.cardTheme.shape as RoundedRectangleBorder).side,
      BorderSide.none,
    );
  });

  test('不明な名前は標準', () {
    expect(DarkVariant.fromName(null), DarkVariant.standard);
    expect(DarkVariant.fromName('soft'), DarkVariant.soft);
  });

  test('文字色の既定は外観ごと', () {
    expect(DarkVariant.standard.defaultTextColor, const Color(0xFFAAAAAA));
    expect(DarkVariant.soft.defaultTextColor, const Color(0xFFD5D5D5));
    expect(DarkVariant.black.defaultTextColor, const Color(0xFFAAAAAA));
    expect(kDefaultTextColorLight, const Color(0xFF71727B));
    expect(kDefaultOnAccentColorLight, const Color(0xFFEFEFF1));
    expect(kDefaultOnAccentColorDark, const Color(0xFFEFEFF1));
  });
}
