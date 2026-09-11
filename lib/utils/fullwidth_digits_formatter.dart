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

/// 日本語IME等で入力された全角数字を強制的に半角へ変換し、それ以外の文字
/// （英字・かな・記号等）は入力させない[TextInputFormatter]。TOTPコード・
/// パスコード入力欄向け（2026-09-06追加、2026-09-11に数字以外の除去を追加）。
class FullwidthDigitsInputFormatter extends TextInputFormatter {
  const FullwidthDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = toHalfWidthDigits(newValue.text);
    final halfWidthValue = converted == newValue.text
        ? newValue
        : newValue.copyWith(text: converted);
    // 数字以外の除去・選択範囲の補正はFlutter標準の実装に委譲する（自前実装
    // しない）。全角数字はASCII外のため、半角変換を済ませた後に渡す順序が
    // 重要（先に`digitsOnly`にかけると全角数字が誤って除去されてしまう）。
    return FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
      oldValue,
      halfWidthValue,
    );
  }
}
