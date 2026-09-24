/// 語らい一覧のレイアウト。端末ごとの個人設定で、自分の画面の見た目だけを
/// 変える。コンピューター（`classifyDevice`が`DeviceClass.computer`）で
/// 横表示の広い画面（`talks_tab.dart`の`_isSplit`）の場合はこの設定を無視し、
/// 常に固定の左右分割表示になる（タブレットの横向きや、狭い画面全般では
/// この設定が適用される）。
enum TalksListLayoutStyle {
  /// 現状の実装。一対/広場を縦積みの1カラムリストで表示し、タップすると
  /// 一番上（最古）の寄合でフルスクリーンチャットへ遷移する。
  standard,

  /// 左にアイコン（＋名前）の一覧、右に選択中の会話の寄合一覧を表示する
  /// 2カラムレイアウト。寄合をタップしてフルスクリーンチャットへ遷移する。
  iconSplit;

  static TalksListLayoutStyle fromName(String? name) {
    return TalksListLayoutStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => TalksListLayoutStyle.standard,
    );
  }
}
