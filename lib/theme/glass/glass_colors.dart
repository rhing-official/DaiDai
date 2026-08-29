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
}
