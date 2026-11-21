/// 一覧の行が、隠れる領域（上部バー・入力欄）を除いた見える範囲に完全に収まって
/// いるか（2026-11-21）。返信先ジャンプで、既に見えている行を動かさない為に使う。
///
/// [leadingEdge]・[trailingEdge]は`ScrollablePositionedList`の`ItemPosition`と同じ、
/// ビューポートに対する割合で、スクロール方向（`reverse: true`なら下から上）に
/// 測る。[bottomInset]は下端の隠れる高さ（入力欄の裏）、[topInset]は上端の
/// 隠れる高さ（上部バーの裏）。
bool isItemFullyVisible({
  required double leadingEdge,
  required double trailingEdge,
  required double viewportHeight,
  required double bottomInset,
  required double topInset,
}) {
  if (viewportHeight <= 0) return false;
  const tolerance = 0.5;
  final bottom = leadingEdge * viewportHeight;
  final top = trailingEdge * viewportHeight;
  return bottom >= bottomInset - tolerance &&
      top <= viewportHeight - topInset + tolerance;
}
