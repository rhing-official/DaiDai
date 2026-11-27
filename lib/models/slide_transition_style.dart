/// 画面遷移（右からのスライドイン・右スワイプで戻る・ローカルNavigatorの画面）の
/// 動きの種類（2026-11-04追加）。端末毎の個人設定で、自分の画面の動きだけを変える。
/// 右スワイプで戻る操作は種類にかかわらず指に追従して動く（操作性を保つため）。
enum SlideTransitionStyle {
  /// スライド＋フェード＋ぼかし（既定）。
  slideBlur,

  /// スライドのみ。
  slide,

  /// 右下の角へ縮みながら吸い込まれていく（2026-11-04、初版・調整前提）。
  suck,

  /// 語らい一覧の「＋」で開くポップアップの動き（2026-11-06）。画面の中央から、
  /// 少し行き過ぎて弾むように拡大しながら現れる（スライドもぼかしも無し）。
  pop,

  /// ペンで往復して、枠も中身も丸ごと描き出す（2026-11-28）。薄くもぼかしもスライドも拡大も
  /// しない。選択の動きの「描き」と同じ[ScribbleReveal]を使う。
  draw;

  /// 重なるページを薄くするか。
  bool get usesFade => this == slideBlur || this == suck || this == pop;

  /// ペンで描き出す動き（[draw]）か。
  bool get usesDraw => this == draw;

  /// 重なるページが離れる間、滲ませるか。
  bool get usesBlur => this == slideBlur || this == suck;

  /// 中央から拡大して現れる動き（[pop]）か。
  bool get usesPopScale => this == pop;

  /// 入場で右からスライドさせるか（吸い込みは縮小で動くのでスライドしない）。
  bool get usesSlide => this != suck && this != pop && this != draw;

  static SlideTransitionStyle fromName(String? name) {
    return SlideTransitionStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => SlideTransitionStyle.pop,
    );
  }
}
