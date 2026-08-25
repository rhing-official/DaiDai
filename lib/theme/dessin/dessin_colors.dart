import 'package:flutter/material.dart';

/// デッサンUIスタイルの固定パレット。アクセントカラー（[accentColorProvider]）
/// とは独立の、このスタイル専用の色。ライト/ダークいずれのthemeModeでも
/// 常にこの配色になる（gekiga_colors.dartと同じ方針）。
class DessinColors {
  DessinColors._();

  /// 紙の下地色（生成りの紙色。純白ではなく僅かに黄味を持たせ「紙」に
  /// 見せる）。
  static const paper = Color(0xFFF4F1E7);

  /// 紙の陰になった部分（相手側の吹き出し等、紙色よりわずかに暗いトーン）。
  static const paperShade = Color(0xFFE7E1D0);

  /// 主線・本文文字の墨色（純黒ではなく僅かに温かみのある濃グレー、鉛筆の
  /// 芯に近い色）。
  static const ink = Color(0xFF2E2C29);

  /// ハッチング・サブテキストに使う中間グレー。
  static const graphite = Color(0xFF6E6A62);

  /// 薄いハッチング・淡い罫線に使う明るいグレー。
  static const graphiteLight = Color(0xFFA79F91);
}
