import 'package:flutter/material.dart';

/// アプリ全体のスクロールの挙動（2026-11-27、ユーザー指示）。上下のスクロールで、上限・下限を
/// 越えて動かせないようにする。iOS・macOSの跳ね返り（バウンス）は`ClampingScrollPhysics`で止め、
/// Androidの端の伸び・光りの表示は、縦方向では出さない。横方向の表示は従来のまま
/// （一対⇄広場の横スワイプは`talks_tab.dart`の`_NoHorizontalOverscroll`が別に消している）。
/// 画面ごとに`physics`を指定している所は、その指定が優先される。
class NoVerticalOverscrollBehavior extends MaterialScrollBehavior {
  const NoVerticalOverscrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.vertical) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }
}
