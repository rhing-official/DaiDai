import 'package:flutter/material.dart';

/// カラーコード文字列⇔Colorの変換。設定画面のカラーコード入力で使う。
extension ColorHex on Color {
  /// 不透明な色は`#RRGGBB`、透明度を含む色は末尾2桁を透明度とした
  /// `#RRGGBBAA` 形式の文字列に変換する。
  String toHexString() {
    final argb = toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    final alpha = argb.substring(0, 2);
    final rgb = argb.substring(2);
    return alpha == 'FF' ? '#$rgb' : '#$rgb$alpha';
  }
}

/// `RRGGBB` / `#RRGGBB` / `RRGGBBAA` / `#RRGGBBAA` を受け付けてColorに変換する。
/// 8桁の場合、末尾2桁（AA）を透明度として扱う（例: `f08300ff`は不透明な`f08300`と同じ色）。
/// 不正な形式の場合はnullを返す。
Color? tryParseHexColor(String input) {
  final hex = input.trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  if (hex.length == 6) return Color(0xFF000000 | value);
  final rgb = value >> 8;
  final alpha = value & 0xFF;
  return Color((alpha << 24) | rgb);
}
