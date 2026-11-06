import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blockはnameで保存・復元出来る', () {
    expect(AppUiStyle.fromName('block'), AppUiStyle.block);
    expect(AppUiStyle.block.name, 'block');
  });

  test('ブロックのテーマはMaterialの影を使わず、ボタンに太い黒枠を付ける', () {
    final theme = BlockTheme.light(const Color(0xFFA855F7));
    final style = theme.elevatedButtonTheme.style!;
    expect(style.elevation!.resolve({}), 0);
    final side = (style.shape!.resolve({}) as RoundedRectangleBorder).side;
    expect(side.color, Colors.black);
    expect(side.width, BlockTheme.borderWidth);
    expect(theme.cardTheme.elevation, 0);
    // ボタンの文字はアクセント色ではなく黒（ライト）。
    expect(style.foregroundColor!.resolve({}), isNot(const Color(0xFFA855F7)));
  });

  test('硬い影はぼかしが無い', () {
    for (final b in Brightness.values) {
      final shadows = BlockTheme.shadow(Colors.purple, b);
      expect(shadows.single.blurRadius, 0);
      expect(shadows.single.offset, BlockTheme.shadowOffset);
    }
  });

  test('ライト・ダークとも、primaryは設定のアクセントカラー（不透明）そのまま', () {
    const accent = Color(0xFF6A4C93);
    expect(BlockTheme.light(accent).colorScheme.primary, accent);
    expect(BlockTheme.dark(accent).colorScheme.primary, accent);
    expect(
      BlockTheme.light(const Color(0xCC6A4C93)).colorScheme.primary,
      accent,
    );
  });

  test('アクセント上の文字色を指定すると、onPrimaryに反映される', () {
    const accent = Color(0xFF6A4C93);
    const custom = Color(0xFFFFEE00);
    expect(BlockTheme.light(accent).colorScheme.onPrimary, Colors.black);
    expect(
      BlockTheme.light(accent, onAccentColor: custom).colorScheme.onPrimary,
      custom,
    );
    expect(
      BlockTheme.dark(accent, onAccentColor: custom).colorScheme.onPrimary,
      custom,
    );
  });
}
