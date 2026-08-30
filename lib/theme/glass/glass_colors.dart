import 'package:flutter/material.dart';

/// ガラスUIの背景色。フラットのダークモード同様、アクセントカラーの
/// 色相に引っ張られない中立色に固定する（マテリアルの縁の光彩だけで
/// アクセントカラーを表現するため、背景まで色づくと「うっすら」感が崩れる）。
class GlassColors {
  GlassColors._();

  static const lightBackground = Color(0xFFF2F2F5);
  static const lightSurfaceBase = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF0E0E12);
  static const darkSurfaceBase = Color(0xFF1C1C22);

  /// ガラスUIの文字・アイコン色。`ColorScheme.fromSeed`任せにすると
  /// アクセントカラーの色相が乗って視認性が落ちるため、ライト/ダーク
  /// それぞれ1色に固定する（2026-08-29追記）。
  static const lightForeground = Color(0xFF1C1C1E);
  static const darkForeground = Color(0xFFF2F2F7);

  /// ガラスUIの通話ボタン等、アイコン単体の文字色として使う場面向けに、
  /// 渡された色をテーマの明暗ごとに視認性の高い色へ調整する
  /// （2026-08-31追加）。固定の`Colors.grey[700]`等は背景色の透けを
  /// 止めた（`GlassSurface.opaque`）後も、ダークモードの近黒背景に対しては
  /// コントラスト不足だったため。無彩色（グレー系、マイク等の中立アイコン）は
  /// [darkForeground]/[lightForeground]にそのまま寄せ、有彩色（通話終了の赤・
  /// 応答の緑など）は色味を保ったまま、ダークモードは明るく・ライトモードは
  /// 暗くしてコントラストを確保する。
  static Color adaptiveIconColor(Color base, Brightness brightness) {
    final hsl = HSLColor.fromColor(base);
    final isDark = brightness == Brightness.dark;
    if (hsl.saturation < 0.05) {
      return isDark ? darkForeground : lightForeground;
    }
    final lightness = isDark
        ? (hsl.lightness < 0.62 ? 0.62 : hsl.lightness)
        : (hsl.lightness > 0.4 ? 0.4 : hsl.lightness);
    return hsl.withLightness(lightness).toColor();
  }
}
