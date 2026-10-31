import 'package:flutter/gestures.dart';
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
    this.enabled = true,
    super.key,
  });

  /// falseなら横スワイプの検出を止める（ハンドラを外すだけで、ウィジェット木の
  /// 形は変えない。`enabled`の切り替えで子（編集中のエディタ等）の状態が
  /// 作り直されないようにするため、2026-10-06変更）。
  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: !enabled
          ? null
          : (details) {
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

/// 水平ドラッグを子孫側で吸収して、外側（祖先）の水平スワイプ（右スワイプで
/// 戻る・タブ切り替え等）に渡さないようにする（2026-10-10追加）。ドローノートは
/// ペン・消しゴムを生のポインタイベント（`Listener`）で取るためジェスチャー
/// アリーナに参加せず、横になぞると外側の水平ドラッグ認識器が勝って画面ごと
/// 閉じてしまっていた。子孫側の認識器は同じスロップ量なら祖先より先に勝つ
/// ため、何もしない水平ドラッグ認識器を置くだけで外側へ渡らなくなる。タップ・
/// ペン/消しゴム（`Listener`）・縦スクロールには影響しない。
class HorizontalDragAbsorber extends StatelessWidget {
  const HorizontalDragAbsorber({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(),
              (recognizer) => recognizer.onUpdate = (_) {},
            ),
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
    this.allowImplicitScrolling = false,
    super.key,
  });

  final PageController controller;

  /// trueなら隣のページも先に作っておく（めくる前に描画を始められる。PDFのように
  /// ページの描画が重いビューア向け）。
  final bool allowImplicitScrolling;
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
  bool _zoomed = false;

  void _reportZoomed(bool zoomed) {
    if (_zoomed == zoomed) return;
    setState(() => _zoomed = zoomed);
  }

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
      allowImplicitScrolling: widget.allowImplicitScrolling,
      physics: isMultiTouch
          ? const NeverScrollableScrollPhysics()
          : const _EasySwipePageScrollPhysics(),
      onPageChanged: (index) {
        // 切り替え先は等倍から始まる。
        if (_zoomed) setState(() => _zoomed = false);
        widget.onPageChanged?.call(index);
      },
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    );
    return ViewerZoomScope(
      report: _reportZoomed,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _incrementPointer,
        onPointerUp: _decrementPointer,
        onPointerCancel: _decrementPointer,
        child: widget.onDismiss == null
            ? pageView
            : SwipeDownToDismiss(
                onDismiss: widget.onDismiss!,
                // 拡大中は下スワイプで閉じず、拡大した内容を動かせるようにする。
                enabled: !isMultiTouch && !_zoomed,
                child: pageView,
              ),
      ),
    );
  }
}

/// 拡大表示中のページが、拡大中かどうかを[PinchPriorityPageView]へ伝えるための
/// 窓口（2026-10-31追加）。拡大中は下スワイプで閉じる操作を止める。
class ViewerZoomScope extends InheritedWidget {
  const ViewerZoomScope({
    required this.report,
    required super.child,
    super.key,
  });

  final ValueChanged<bool> report;

  static ValueChanged<bool>? maybeReportOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ViewerZoomScope>()?.report;

  @override
  bool updateShouldNotify(ViewerZoomScope oldWidget) => false;
}

/// [controller]（`InteractiveViewer`の`TransformationController`）の拡大率を
/// 見て、拡大中かどうかを[ViewerZoomScope]へ報告する。拡大中の判定は、
/// タップで閉じる判定と同じ1.01倍超。
class ZoomReporter extends StatefulWidget {
  const ZoomReporter({
    required this.controller,
    required this.child,
    super.key,
  });

  final TransformationController controller;
  final Widget child;

  @override
  State<ZoomReporter> createState() => _ZoomReporterState();
}

class _ZoomReporterState extends State<ZoomReporter> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ZoomReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final zoomed = widget.controller.value.getMaxScaleOnAxis() > 1.01;
    ViewerZoomScope.maybeReportOf(context)?.call(zoomed);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// マウスホイールのスクロールを、子孫のスクロール領域が端に達した後も外側
/// （メッセージ一覧等）へ渡さないようにする（2026-10-31追加）。内側が
/// スクロールできる間は内側が先に処理し、端で内側が受け取らなくなった時だけ
/// ここで消費する。[enabled]がfalseなら何もしない（従来どおり外側へ渡る）。
class WheelScrollAbsorber extends StatelessWidget {
  const WheelScrollAbsorber({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
        }
      },
      child: child,
    );
  }
}
