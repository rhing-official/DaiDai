/// メッセージの前後にある余分な空白・改行・見えない文字を取り除く（2026-11-21）。
///
/// `String.trim()`は半角・全角スペース、改行、タブ、NBSPなどを取り除くが、
/// コピー＆ペーストで混ざりやすいゼロ幅スペース等は残る為、それも対象にする。
/// 本文の途中は変えない。
String trimMessage(String text) {
  bool invisible(int unit) =>
      unit == 0x200B ||
      unit == 0x200C ||
      unit == 0x200D ||
      unit == 0x2060 ||
      unit == 0x180E ||
      unit == 0xFEFF;

  var start = 0;
  var end = text.length;
  while (start < end) {
    final ch = text.substring(start, start + 1);
    if (invisible(ch.codeUnitAt(0)) || ch.trim().isEmpty) {
      start++;
    } else {
      break;
    }
  }
  while (end > start) {
    final ch = text.substring(end - 1, end);
    if (invisible(ch.codeUnitAt(0)) || ch.trim().isEmpty) {
      end--;
    } else {
      break;
    }
  }
  return text.substring(start, end);
}
