import 'package:flutter/material.dart';

/// ダークモードの種類（2026-11-17追加、Discordの Dark / Ash / Onyx に倣う）。
///
/// 背景・カード面はアクセントカラーに依存しない中立色で、種類だけで決まる。
/// 「標準」は従来のダークと同じ値（既存の見た目は変えない）。フラット・版画は
/// [background]/[surface]、ガラスは専用パレットの[glassBackground]/
/// [glassSurface]を使う。劇画は固定の見た目のため対象外。
enum DarkVariant {
  /// 墨（Ink）。従来のダーク。
  standard(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    glassBackground: Color(0xFF0E0E12),
    glassSurface: Color(0xFF1C1C22),
    defaultTextColor: Color(0xFFAAAAAA),
  ),

  /// 鈍色（Slate）。少し明るく柔らかいダーク（Ash相当）。
  soft(
    background: Color(0xFF2A2A2D),
    surface: Color(0xFF38383C),
    glassBackground: Color(0xFF23232B),
    glassSurface: Color(0xFF32323C),
    defaultTextColor: Color(0xFFD5D5D5),
  ),

  /// 漆黒（Jet）。完全な黒（Onyx相当、有機ELの省電力）。面が背景に溶けないよう、カード等には
  /// [outline]の細い枠を付ける。
  black(
    background: Color(0xFF000000),
    surface: Color(0xFF0D0D0D),
    glassBackground: Color(0xFF000000),
    glassSurface: Color(0xFF0B0B0E),
    defaultTextColor: Color(0xFFAAAAAA),
    outline: Color(0xFF2E2E2E),
  );

  const DarkVariant({
    required this.background,
    required this.surface,
    required this.glassBackground,
    required this.glassSurface,
    required this.defaultTextColor,
    this.outline,
  });

  final Color background;
  final Color surface;
  final Color glassBackground;
  final Color glassSurface;

  /// 主な文字（フォントカラー）の既定色（2026-11-18）。ユーザーが色を保存していない時に使う。
  final Color defaultTextColor;

  /// カード等に付ける枠線の色。null=枠線を足さない。
  final Color? outline;

  static DarkVariant fromName(String? name) => DarkVariant.values.firstWhere(
    (v) => v.name == name,
    orElse: () => DarkVariant.standard,
  );
}
