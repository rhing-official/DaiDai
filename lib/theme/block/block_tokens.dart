import 'package:flutter/material.dart';

/// 版画（[BlockTheme]）の形と線の色を決める数値の組（2026-11-26、素材パック用）。
///
/// 既定値は従来の版画のまま。素材パックを適用している間だけ、パックの値に差し替わる
/// （[BlockTokens.current]）。`BlockTheme.borderWidth`等の既存の呼び出しは、ここを読む。
@immutable
class BlockTokens {
  const BlockTokens({
    this.borderWidth = 2.5,
    this.radius = 8.0,
    this.shadowOffset = const Offset(4, 4),
    this.lightLine = Colors.black,
    this.darkLine = const Color(0xFFEDEDED),
  });

  /// 枠線の太さ。
  final double borderWidth;

  /// 角丸。
  final double radius;

  /// 硬い影のずらし量。
  final Offset shadowOffset;

  /// ライトの枠・影の色／ダークの枠・影の色。
  final Color lightLine;
  final Color darkLine;

  /// 今の値。素材パックの切り替えで差し替わる。
  static BlockTokens current = const BlockTokens();
}
