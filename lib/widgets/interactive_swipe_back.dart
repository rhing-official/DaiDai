import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'swipe_gestures.dart';

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
/// 元の位置へアニメーションで復帰する。
///
/// 左スワイプ（[alsoSwipeLeft]）は既存の[SwipeBackDetector]と同じ、
/// 離した瞬間の速度判定のみの挙動を維持する（インタラクティブ化の
/// 対象は右スワイプのみ）。
class InteractiveSwipeBackTransition extends StatefulWidget {
  const InteractiveSwipeBackTransition({
    required this.onBack,
    required this.child,
    this.alsoSwipeLeft = false,
    super.key,
  });

  final VoidCallback onBack;
  final bool alsoSwipeLeft;
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller.maxDrag = MediaQuery.sizeOf(context).width;
    return InteractiveSwipeBackScope(
      controller: _controller,
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
          if (!_controller.isGestureActive) {
            final velocity = details.primaryVelocity ?? 0;
            if (widget.alsoSwipeLeft &&
                velocity <= -kSwipeGestureVelocityThreshold) {
              widget.onBack();
            }
            return;
          }
          _controller.endExternalDrag(context, details.primaryVelocity);
        },
        child: ValueListenableBuilder<double>(
          valueListenable: _controller.progress,
          child: RepaintBoundary(child: widget.child),
          builder: (context, value, child) {
            return Transform.translate(offset: Offset(value, 0), child: child);
          },
        ),
      ),
    );
  }
}
