/// カタカナ→ひらがな変換＋大文字小文字統一。「ありがとう」と「アリガトウ」、
/// "OK"と"ok"のような表記ゆれを部分一致の対象として吸収するための簡易正規化
/// （元は`sticker_suggestion.dart`の私有関数だったものを、`spam_check.dart`
/// （技術仕様書8.3レイヤー3）でも同じロジックが必要になったため共通化した、
/// 2026-09-07）。
String normalizeForMatch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    // カタカナ（ァ-ヶ、0x30A1-0x30F6）は+0x60した位置に対応するひらがな
    // （ぁ-ゖ、0x3041-0x3096）があるため、そのまま引き算で変換できる。
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
