import 'package:flutter/services.dart';

/// 全角数字（U+FF10〜U+FF19）を半角数字（U+0030〜U+0039）に変換する。
/// [kana_sort.dart]の`compareKana`と同様、Unicodeコードポイントの
/// オフセット演算による変換（2026-09-06追加）。
String toHalfWidthDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// 日本語IME等で入力された全角数字を強制的に半角へ変換する
/// [TextInputFormatter]。TOTPコード入力欄向け（2026-09-06追加）。
class FullwidthDigitsInputFormatter extends TextInputFormatter {
  const FullwidthDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = toHalfWidthDigits(newValue.text);
    if (converted == newValue.text) return newValue;
    return newValue.copyWith(text: converted);
  }
}
