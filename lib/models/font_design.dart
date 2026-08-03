/// メニュー・見出しに使うフォントデザイン。端末ごとの個人設定で、自分の画面の
/// 見た目だけを変える（相手の語らいの表示には一切影響しない）。
///
/// [gekiga]は劇画UIスタイル（`AppUiStyle.gekiga`）が選択されている場合のみ
/// 選択可能（劇画フォントはCJKグリフを持たず、劇画UI以外では見た目上の効果が
/// 無いため。設定UI側で選択自体を無効化する）。
enum FontDesign {
  /// システム標準フォントのまま。
  standard,

  /// 劇画UIスタイル用の見出し・メニューフォント（Persona5MenuFontPrototype）。
  gekiga;

  static FontDesign fromName(String? name) {
    return FontDesign.values.firstWhere(
      (design) => design.name == name,
      orElse: () => FontDesign.standard,
    );
  }
}
