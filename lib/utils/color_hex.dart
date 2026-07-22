import 'package:flutter/material.dart';

/// カラーコード文字列⇔Colorの変換。設定画面のカラーコード入力で使う。
extension ColorHex on Color {
  /// `#RRGGBB` 形式の文字列に変換する。
  String toHexString() {
    final argb = toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }
}

/// `RRGGBB` / `#RRGGBB` / `RRGGBBAA` / `#RRGGBBAA` を受け付けてColorに変換する。
/// 不正な形式の場合はnullを返す。
Color? tryParseHexColor(String input) {
  final hex = input.trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return hex.length == 6 ? Color(0xFF000000 | value) : Color(value);
}
