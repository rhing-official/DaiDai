/// アプリの見た目のスタイル。設定タブから切り替えられる。
enum UiStyle {
  /// 標準のDaiDaiスタイル（橙色 #EE7800 基調）。
  daidai,

  /// シンプルスタイル。配色・等幅フォント・余白多めのミニマルなレイアウトを採用する。
  simple;

  static UiStyle fromName(String? name) {
    return UiStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => UiStyle.daidai,
    );
  }
}
