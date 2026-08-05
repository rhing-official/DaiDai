/// [name]が[maxLength]文字を超える場合、先頭[maxLength]文字＋「…」に
/// 短縮する。文字数以内ならそのまま返す（一対名・広場名・寄合名など、
/// 一覧のブロックが長い名前で不必要に大きくなるのを防ぐための共通処理）。
String truncateName(String name, int maxLength) {
  if (name.length <= maxLength) return name;
  return '${name.substring(0, maxLength)}…';
}
