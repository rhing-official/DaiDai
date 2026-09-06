import 'package:flutter/material.dart';

/// スワイプジェスチャーを「切り替え」ではなく「戻る／閉じる」操作として
/// 扱うための共通しきい値・ラッパー（2026-07-25）。
/// 以前はホーム画面全体を覆うジェスチャーで4タブ（語らい/身だしなみ/設定/運営）を
/// 切り替えていたが、ポップアップ等のオーバーレイ上ではバリアがジェスチャーを
/// 吸収してしまい一貫して動作しなかったため廃止し、代わりに各画面が持つ
/// 「戻る」操作（設定・身だしなみ・運営タブの狭い画面でのカテゴリ一覧への
/// ドリルダウン、go_routerでpushした各画面のpop）に個別にスワイプを割り当てる。
const kSwipeGestureVelocityThreshold = 75.0;

/// 右方向への横スワイプで[onPrevious]（無ければ[onBack]）を、
/// 左方向への横スワイプで[onNext]を呼ぶ。
/// [onPrevious]・[onNext]を省略した場合は、右スワイプで常に[onBack]、
/// 左スワイプは何もしない（従来通りの「戻るだけ」の挙動）。
/// 設定・身だしなみ・運営タブの狭い画面ドリルダウンでは、隣接カテゴリへの
/// 切り替え（[onPrevious]/[onNext]）と一覧への「戻る」（[onBack]、先頭
/// カテゴリで右スワイプしたとき）を両立させるためにこの3引数を使う。
class SwipeBackDetector extends StatelessWidget {
  const SwipeBackDetector({
    required this.onBack,
    required this.child,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity >= kSwipeGestureVelocityThreshold) {
          (onPrevious ?? onBack)();
        } else if (velocity <= -kSwipeGestureVelocityThreshold) {
          onNext?.call();
        }
      },
      child: child,
    );
  }
}

/// 下方向への縦スワイプで[onDismiss]を呼ぶ。ポップアップ（Dialog）を
/// 下にスライドして閉じる操作に使う。[enabled]をfalseにすると縦スワイプの
/// 検出自体を止める（[PinchPriorityPageView]がピンチ操作中に使う、
/// 2026-09-02追加）。
class SwipeDownToDismiss extends StatelessWidget {
  const SwipeDownToDismiss({
    required this.onDismiss,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onDismiss;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: !enabled
          ? null
          : (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity >= kSwipeGestureVelocityThreshold) onDismiss();
            },
      child: child,
    );
  }
}

/// `PageView`既定の`PageScrollPhysics`は、フリングが無いゆっくりしたドラッグ
/// では「ページ幅の50%（`page.roundToDouble()`）」を超えないと次のページに
/// 確定しない。これがメディアビューアの「かなり大きくスワイプしないと
/// 反応しない」というUX上の指摘（2026-09-06）の原因だったため、確定条件を
/// ページ幅の10%まで緩和したもの（当初20%へ緩和したが、同日さらに半分へ
/// 再緩和）。フリング時（速度がしきい値を超える場合）の
/// 「距離に関わらず1ページ分確定する」挙動は元の`PageScrollPhysics`と同じ
/// （Flutter本体`page_view.dart`の`_getTargetPixels`と同じ構造）。
class _EasySwipePageScrollPhysics extends PageScrollPhysics {
  const _EasySwipePageScrollPhysics({super.parent});

  static const double _commitThreshold = 0.1;

  @override
  _EasySwipePageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _EasySwipePageScrollPhysics(parent: buildParent(ancestor));

  double _getTargetPixels(
    ScrollMetrics position,
    Tolerance tolerance,
    double velocity,
  ) {
    // このアプリの`PageView`は全てviewportFraction既定値(1.0)のため、
    // ページ<->pixel変換はviewportDimensionでの単純な比例計算でよい
    // （SDK本体の`PageScrollPhysics`が内部で使う`_PagePosition`は非公開の
    // ためここでは使えない）。
    var page = position.pixels / position.viewportDimension;
    if (velocity.abs() > tolerance.velocity) {
      page += velocity.sign * 0.5;
    } else {
      final nearest = page.roundToDouble();
      final diff = page - nearest;
      page = diff.abs() >= _commitThreshold ? nearest + diff.sign : nearest;
    }
    return page.roundToDouble() * position.viewportDimension;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}

/// 画像/動画のフルスクリーンビューアで`PageView`（横スワイプでページ送り）と
/// `InteractiveViewer`（ピンチズーム）を重ねると、ジェスチャーアリーナの
/// 勝敗判定が確定するまでピンチが`InteractiveViewer`に渡らず、「反応が遅く
/// 後から一気にズームインする」「画像の外側でピンチしても反応しない」ように
/// 見える不具合が起きる（2026-09-02判明）。2本指（ピンチ）が画面に触れている
/// 間は`PageView`のページ送り・[onDismiss]の下スワイプ検出そのものを止め、
/// `InteractiveViewer`のスケール認識と競合しないようにする。
class PinchPriorityPageView extends StatefulWidget {
  const PinchPriorityPageView({
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.onDismiss,
    super.key,
  });

  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;

  /// nullなら[SwipeDownToDismiss]自体でラップしない（アルバムビューアのように
  /// 下スワイプで閉じる操作を持たない画面向け）。
  final VoidCallback? onDismiss;

  @override
  State<PinchPriorityPageView> createState() => _PinchPriorityPageViewState();
}

class _PinchPriorityPageViewState extends State<PinchPriorityPageView> {
  int _pointerCount = 0;

  void _incrementPointer(PointerDownEvent _) {
    setState(() => _pointerCount++);
  }

  void _decrementPointer(PointerEvent _) {
    if (_pointerCount == 0) return;
    setState(() => _pointerCount--);
  }

  @override
  Widget build(BuildContext context) {
    final isMultiTouch = _pointerCount >= 2;
    final pageView = PageView.builder(
      controller: widget.controller,
      physics: isMultiTouch
          ? const NeverScrollableScrollPhysics()
          : const _EasySwipePageScrollPhysics(),
      onPageChanged: widget.onPageChanged,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _incrementPointer,
      onPointerUp: _decrementPointer,
      onPointerCancel: _decrementPointer,
      child: widget.onDismiss == null
          ? pageView
          : SwipeDownToDismiss(
              onDismiss: widget.onDismiss!,
              enabled: !isMultiTouch,
              child: pageView,
            ),
    );
  }
}
