import 'package:flutter/material.dart' show kMinInteractiveDimension;
import 'package:flutter/rendering.dart' show Offset;

/// 「指を触れたまま滑らせて選ぶ」ドラッグ選択メニュー1行分の見た目上の高さ。
/// 算術での当たり判定を前提にするため、各項目ラベルは折り返さず1行固定にする。
const double kDragMenuItemHeight = kMinInteractiveDimension;

/// ドラッグ選択メニュー表示中、押した指の位置からどの項目の上にいるかを
/// 算術で求める（個々のウィジェットの`RenderBox`計測に頼らない）。範囲外なら-1。
///
/// 元々はメッセージの長押しメニュー（`_MessageBubbleTapArea`、
/// `lib/features/chat/chat_screen.dart`、2026-08-09追加）専用の実装だったが、
/// メッセージ入力欄の＋ボタンの添付ポップアップ（`AttachmentPopupButton`、
/// 2026-08-10追加）でも同じ「押すとすぐ開き、指を離さずスワイプしても選べる」
/// UXを流用するため、共通ユーティリティとして切り出した。
class DragMenuGeometry {
  const DragMenuGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.itemCount,
  });

  final double left;
  final double top;
  final double width;
  final int itemCount;

  double get height => kDragMenuItemHeight * itemCount;

  int hitTest(Offset globalPosition) {
    if (globalPosition.dx < left || globalPosition.dx > left + width) {
      return -1;
    }
    final relativeY = globalPosition.dy - top;
    if (relativeY < 0 || relativeY >= height) return -1;
    return (relativeY / kDragMenuItemHeight).floor().clamp(0, itemCount - 1);
  }
}
