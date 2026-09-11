/// 縦表示（狭い画面）での語らい一覧のレイアウト。端末ごとの個人設定で、
/// 自分の画面の見た目だけを変える。
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
