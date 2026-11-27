import 'package:flutter/material.dart';

import '../utils/bubble_colors.dart';

/// ダークモードの種類（2026-11-17追加、Discordの Dark / Ash / Onyx に倣う）。
///
/// 背景・カード面はアクセントカラーに依存しない中立色で、種類だけで決まる。
/// 「標準」は従来のダークと同じ値（既存の見た目は変えない）。フラット・版画は
/// [background]/[surface]、ガラスは専用パレットの[glassBackground]/
/// [glassSurface]を使う。劇画は固定の見た目のため対象外。
/// 外観の背景・面・枠の色の組（2026-11-26）。[DarkVariant]の値、または、カスタムの外観
/// （背景色のカラーコード）から作る。テーマは、この組を使って色を決める。
/// 暗い背景の明度の上限と、明るい背景の明度の下限。[AppearancePalette.normalizeBackground]。
const double kDarkBackgroundMaxLightness = 0.20;
const double kLightBackgroundMinLightness = 0.85;

@immutable
class AppearancePalette {
  const AppearancePalette({
    required this.background,
    required this.surface,
    required this.glassBackground,
    required this.glassSurface,
    this.outline,
  });

  /// 背景色[c]から、面の色を導く。[c]の明るさで、面を明るく（暗い背景）か、暗く（明るい背景）
  /// する。
  ///
  /// 背景は、先に[normalizeBackground]で、明るさを帯に収める（2026-11-27）。真ん中の明るさの
  /// 背景では、文字や吹き出しとの差を、固定のずらし方で保てないため。[surface]を渡すと、面の色は
  /// それにする（意匠のパネルの色）。
  factory AppearancePalette.fromBackground(Color c, {Color? surface}) {
    final bg = normalizeBackground(c);
    final dark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    final derived = Color.lerp(bg, dark ? Colors.white : Colors.black, 0.07)!;
    final face = surface ?? derived;
    return AppearancePalette(
      background: bg,
      surface: face,
      glassBackground: bg,
      glassSurface: face,
    );
  }

  /// 背景の明るさを、暗い帯（明度20%以下）か明るい帯（明度85%以上）に収める。色相と彩度は
  /// そのまま。帯の中にある色は、近い方の端へ寄せる。保存値は変えず、表示の時だけ使う。
  static Color normalizeBackground(Color c) {
    final hsl = HSLColor.fromColor(c);
    final l = hsl.lightness;
    if (l <= kDarkBackgroundMaxLightness || l >= kLightBackgroundMinLightness) {
      return c;
    }
    final target =
        l < (kDarkBackgroundMaxLightness + kLightBackgroundMinLightness) / 2
        ? kDarkBackgroundMaxLightness
        : kLightBackgroundMinLightness;
    return hsl.withLightness(target).toColor().withValues(alpha: c.a);
  }

  /// 一覧の選択中の塗り。アクセントカラーを、背景の上に[alpha]の不透明度で重ねた不透明な色
  /// （ガラスの選択ブロックは45%）。画面に透けて見える色を、先に合成しておく。
  Color selectionFill(Color accent, {double alpha = 1.0}) =>
      Color.alphaBlend(accent.withValues(alpha: accent.a * alpha), background);

  /// 一覧・吹き出しの下地の色。ガラスは、面を[glassTintAlpha]の不透明度で背景に重ねた色。
  /// それ以外は背景そのもの。メンションの強調などが、下地に合わせた色を作るのに使う。
  Color listBase({required bool glass, double glassTintAlpha = 0.6}) => glass
      ? Color.alphaBlend(surface.withValues(alpha: glassTintAlpha), background)
      : background;

  /// 吹き出しの塗り色（相手は背景から離した色、自分はそれにアクセントカラーを混ぜた色）。
  Color bubbleFill({
    required bool isMe,
    required Color accent,
    double strength = 1.0,
  }) => chatBubbleFill(
    background: background,
    accent: accent,
    isMe: isMe,
    strength: strength,
  );

  final Color background;
  final Color surface;
  final Color glassBackground;
  final Color glassSurface;
  final Color? outline;
}

enum DarkVariant {
  /// 墨（Ink）。従来のダーク。
  standard(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    glassBackground: Color(0xFF0E0E12),
    glassSurface: Color(0xFF1C1C22),
    defaultTextColor: Color(0xFFD5D5D5),
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
    defaultTextColor: Color(0xFFD5D5D5),
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

  AppearancePalette get palette => AppearancePalette(
    background: background,
    surface: surface,
    glassBackground: glassBackground,
    glassSurface: glassSurface,
    outline: outline,
  );

  static DarkVariant fromName(String? name) => DarkVariant.values.firstWhere(
    (v) => v.name == name,
    orElse: () => DarkVariant.standard,
  );
}
