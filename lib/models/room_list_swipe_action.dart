/// 縦表示（スマホ）の「アイコン＋寄合一覧」で、寄合一覧の上の横スワイプに割り当てる
/// 動作（2026-11-08）。
enum RoomListSwipeAction {
  /// 左へスワイプすると、選択中の寄合のメッセージ画面を開く。先に右へスワイプした時は、
  /// 離すまで隣のメニューチップのタブへの切り替えになる（これまでの動き）。
  openRoom,

  /// 左右どちらへスワイプしても、隣のメニューチップのタブへ切り替える。メッセージ画面は
  /// スワイプでは開かない（寄合のタップで開く）。標準（2026-11-15に`openRoom`から変更）。
  switchTab;

  static RoomListSwipeAction fromName(String? name) => name == 'openRoom'
      ? RoomListSwipeAction.openRoom
      : RoomListSwipeAction.switchTab;
}
