/// アクセントカラーの固定プリセット（8桁hex＝RRGGBBAA）。フラット/ガラス/劇画の
/// 3スタイル共通の1リスト（2026-09-15）。カードの文字色のプリセットも、この
/// 色（アルファを落とした不透明の色）を引用する（2026-10-31）。
const kDefaultColorPresets = [
  'F08300CC',
  '3D2EE0CC',
  '88B04BCC',
  'C1272DCC',
  'F08567CC',
  '114514CC',
  'A997C6CC',
  '114789CC',
];

/// カードの文字色の固定プリセット（6桁hex＝RRGGBB）。アクセントの固定プリセットを
/// 不透明にした色に、白（標準）を足した8種類。
final List<String> kFontColorPresets = [
  for (final hex in kDefaultColorPresets) hex.substring(0, 6),
  'FFFFFF',
];
