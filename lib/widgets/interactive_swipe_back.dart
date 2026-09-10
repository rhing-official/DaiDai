import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'swipe_gestures.dart';

/// トラックパッド/マウスホイールの水平スクロールで「戻る」を発火させる
/// 際のしきい値（px、2026-09-10追加）。`embedded_call_pane.dart`の縦方向
/// 実装（`dy < -2.0`）に倣った値。
const kSwipeBackScrollThreshold = 2.0;

/// ゆっくり指を離した場合に「戻る」を確定させる、画面幅に対する位置の
/// 閾値（0.4 = 40%）。フリックの場合は[kSwipeGestureVelocityThreshold]の
/// 速度判定を優先する。
const kSwipeBackPositionThreshold = 0.4;

/// 語らい画面の右スワイプ「戻る」ジェスチャーの進行状態を保持し、
/// ドラッグ中の追従・指を離した時のコミット（戻る）／キャンセル（復帰）を
/// 判定・アニメーションするコントローラ（2026-09-07追加）。
///
/// 背景（[InteractiveSwipeBackTransition]自身のGestureDetector）と、
/// メッセージ吹き出し上のドラッグ（`chat_screen.dart`の
/// `_MessageInteractionsState`）の両方から、常に「現在の絶対px」で
/// [syncFromExternalDrag]を呼ぶ設計にすることで、差分の二重積算を避ける。
class InteractiveSwipeBackController {
  InteractiveSwipeBackController({
    required TickerProvider vsync,
    required this.onCommit,
  }) : _animationController = AnimationController(vsync: vsync);

  final VoidCallback onCommit;
  final AnimationController _animationController;

  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// 呼び出し側（[InteractiveSwipeBackTransition]）が都度反映する画面幅。
  double maxDrag = 1;

  bool isGestureActive = false;

  void syncFromExternalDrag(BuildContext context, double absoluteOffsetPx) {
    if (!isGestureActive) {
      isGestureActive = true;
      _animationController.stop();
      Navigator.of(context).didStartUserGesture();
    }
    progress.value = absoluteOffsetPx.clamp(0.0, maxDrag);
  }

  void endExternalDrag(BuildContext context, double? velocityPxPerSec) {
    if (!isGestureActive) return;
    isGestureActive = false;

    final velocity = velocityPxPerSec ?? 0;
    final bool commit;
    if (velocity <= -kSwipeGestureVelocityThreshold) {
      commit = false;
    } else if (velocity >= kSwipeGestureVelocityThreshold) {
      commit = true;
    } else {
      commit = progress.value / maxDrag >= kSwipeBackPositionThreshold;
    }

    final start = progress.value;
    final target = commit ? maxDrag : 0.0;
    final remaining = (target - start).abs();
    final fraction = maxDrag == 0 ? 0.0 : remaining / maxDrag;
    final duration = Duration(
      milliseconds: (popSlideDuration.inMilliseconds * fraction).round().clamp(
        120,
        popSlideDuration.inMilliseconds,
      ),
    );

    Navigator.of(context).didStopUserGesture();

    _animationController
      ..duration = duration
      ..value = 0;
    final animation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _animationController, curve: popSlideCurve),
    );
    void listener() => progress.value = animation.value;
    animation.addListener(listener);
    _animationController.forward().whenCompleteOrCancel(() {
      animation.removeListener(listener);
      if (commit) onCommit();
    });
  }

  void dispose() {
    _animationController.dispose();
    progress.dispose();
  }
}

/// [InteractiveSwipeBackController]を子孫（メッセージ吹き出しの
/// ドラッグハンドラ）へ配布するための非購読ルックアップ用スコープ。
/// コントローラのインスタンスはルートの生存期間中不変なので、
/// 値の変化を購読する必要は無い。
class InteractiveSwipeBackScope extends InheritedWidget {
  const InteractiveSwipeBackScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final InteractiveSwipeBackController controller;

  static InteractiveSwipeBackController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<InteractiveSwipeBackScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(InteractiveSwipeBackScope oldWidget) => false;
}

/// 語らい画面（[DmChatPane]/[GroupChatPane]相当）を右スワイプで
/// インタラクティブに戻れるようにするラッパー（2026-09-07追加）。
/// ドラッグ中は指の位置にリアルタイムに追従して[child]全体が右へ
/// スライドし、一覧画面（Navigatorスタック上で下に残っている画面）が
/// 見えるようになる。指を離した時、閾値を超えていれば画面外まで
/// スライドし切ってから[onBack]（戻る）を呼び、超えていなければ
/// 元の位置へアニメーションで復帰する。トラックパッド/マウスホイールの
/// 右スクロールでも同じく[onBack]を呼ぶ（`_handleScroll`参照）。
///
/// 左スワイプでの「戻る」は以前は対応していたが（`alsoSwipeLeft`、
/// ユーザー要望で追加）、誤操作につながるとの判断で2026-09-10に廃止した。
/// 現在は右方向（ドラッグ・スクロールとも）のみが「戻る」に対応する。
class InteractiveSwipeBackTransition extends StatefulWidget {
  const InteractiveSwipeBackTransition({
    required this.onBack,
    required this.child,
    super.key,
  });

  final VoidCallback onBack;
  final Widget child;

  @override
  State<InteractiveSwipeBackTransition> createState() =>
      _InteractiveSwipeBackTransitionState();
}

class _InteractiveSwipeBackTransitionState
    extends State<InteractiveSwipeBackTransition>
    with SingleTickerProviderStateMixin {
  late final InteractiveSwipeBackController _controller =
      InteractiveSwipeBackController(vsync: this, onCommit: widget.onBack);

  double _cumulativeDx = 0;

  /// トラックパッド/マウスホイールの水平スクロールで「戻る」を発火させる
  /// 際のデバウンス用タイマー（2026-09-10追加、`_handleScroll`参照）。
  Timer? _scrollBackTimer;

  @override
  void dispose() {
    _scrollBackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// コンピューターUI（タッチではなくトラックパッド/マウスホイール操作）
  /// 向けに、指ドラッグでの右スワイプと同じ「戻る」を右スクロールでも
  /// 行えるようにする（2026-09-10追加）。`embedded_call_pane.dart`の
  /// 縦方向実装（上スクロールで「戻る」）と同じ、離散的なスクロール
  /// イベントを150msデバウンスしてから直接[onBack]を呼ぶだけの単純な
  /// 実装で、ドラッグ版のような追従アニメーションは行わない（トラック
  /// パッドのスクロールには連続した「指の位置」に相当する情報が無いため）。
  ///
  /// メッセージ一覧（[widget.child]内の`ChatScreen`のListView）は縦
  /// スクロールが主用途のため、縦方向が主のスクロール中に横方向の微小な
  /// ノイズで誤って「戻る」が発火しないよう、横方向が縦方向より明確に
  /// 大きいことを条件にする（`embedded_call_pane.dart`等の縦方向のみの
  /// 既存実装には無いガード。それらは元々縦スクロールしかしない画面
  /// だったため不要だった）。
  void _handleScroll(PointerScrollEvent event) {
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (dx <= kSwipeBackScrollThreshold || dx.abs() <= dy.abs()) return;
    _scrollBackTimer?.cancel();
    _scrollBackTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) widget.onBack();
    });
  }

  @override
  Widget build(BuildContext context) {
    _controller.maxDrag = MediaQuery.sizeOf(context).width;
    return InteractiveSwipeBackScope(
      controller: _controller,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) _handleScroll(event);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _cumulativeDx = _controller.progress.value;
          },
          onHorizontalDragUpdate: (details) {
            _cumulativeDx += details.delta.dx;
            if (_cumulativeDx > 0 || _controller.isGestureActive) {
              _controller.syncFromExternalDrag(
                context,
                _cumulativeDx.clamp(0.0, _controller.maxDrag),
              );
            }
          },
          onHorizontalDragEnd: (details) {
            if (!_controller.isGestureActive) return;
            _controller.endExternalDrag(context, details.primaryVelocity);
          },
          child: ValueListenableBuilder<double>(
            valueListenable: _controller.progress,
            child: RepaintBoundary(child: widget.child),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(value, 0),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}
