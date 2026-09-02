/// 語らい一覧の「五十音順」並べ替え用の比較関数。DaiDaiは相手の呼び名・
/// 広場名の読み仮名データを持たないため、厳密な五十音順は実現できない。
/// 代わりに先頭文字が属する文字種（ひらがな→カタカナ→漢字→それ以外）で
/// 大まかに分類し、同じ文字種内はUnicodeコードポイント順で比較する
/// （ひらがな/カタカナはUnicodeの並びがほぼ50音順と一致するため、実用上
/// 問題ない近似になる。漢字は読み情報が無い以上、コードポイント順が唯一の
/// 決定的な代替）。2026-09-02追加。
int compareKana(String a, String b) {
  final categoryDiff = _kanaCategory(a) - _kanaCategory(b);
  if (categoryDiff != 0) return categoryDiff;
  return a.compareTo(b);
}

int _kanaCategory(String s) {
  if (s.isEmpty) return 3;
  final code = s.runes.first;
  if (code >= 0x3041 && code <= 0x3096) return 0; // ひらがな
  if ((code >= 0x30A1 && code <= 0x30FA) ||
      (code >= 0x31F0 && code <= 0x31FF)) {
    return 1; // カタカナ（0x31F0-0x31FFはアイヌ語表記の拡張カタカナ）
  }
  if (code >= 0x4E00 && code <= 0x9FFF) return 2; // 漢字（CJK統合漢字）
  return 3; // それ以外（英数字・記号等）
}
