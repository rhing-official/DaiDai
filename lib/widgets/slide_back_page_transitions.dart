import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'interactive_swipe_back.dart';
import 'swipe_gestures.dart';

/// ローカル`Navigator`でpushされたルート向けの、右からのスライド入場と
/// 右スワイプで戻る操作（2026-10-16追加）。設定のオープンソースライセンスの
/// パッケージ詳細（`LicensePage`が`MaterialPageRoute`をpushするため、ルート
/// 自体は差し替えられず、`Theme`の`pageTransitionsTheme`経由で適用する）に使う。
///
/// ドラッグ中はルート自身のアニメーションを動かす（`PredictiveBackRoute`の
/// 公開API）。画面全体を`Transform`で動かす[InteractiveSwipeBackTransition]
/// と違い、ルートが半透明扱いになって直下のルート（一覧）が見え、離した
/// 後も現在位置から右へそのまま消える。
class SlideBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SlideBackPageTransitionsBuilder();

  /// 全プラットフォームへこのビルダーを割り当てた[PageTransitionsTheme]。
  static const theme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: SlideBackPageTransitionsBuilder(),
      TargetPlatform.iOS: SlideBackPageTransitionsBuilder(),
      TargetPlatform.macOS: SlideBackPageTransitionsBuilder(),
      TargetPlatform.windows: SlideBackPageTransitionsBuilder(),
      TargetPlatform.linux: SlideBackPageTransitionsBuilder(),
      TargetPlatform.fuchsia: SlideBackPageTransitionsBuilder(),
    },
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // 指に追従する間は直線、それ以外は入場と同じカーブ。
        final t = route.popGestureInProgress
            ? animation.value
            : popSlideCurve.transform(animation.value);
        return FractionalTranslation(
          translation: Offset(1 - t, 0),
          child: child,
        );
      },
    );
    // 最初のルート（一覧）には戻る先が無い。
    if (route.isFirst) return slide;
    return _RouteBackSwipe(route: route, child: slide);
  }
}

class _RouteBackSwipe extends StatefulWidget {
  const _RouteBackSwipe({required this.route, required this.child});

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_RouteBackSwipe> createState() => _RouteBackSwipeState();
}

class _RouteBackSwipeState extends State<_RouteBackSwipe> {
  double _dx = 0;
  bool _active = false;

  double get _width => (context.size?.width ?? 1).clamp(1.0, double.infinity);

  void _update() {
    final progress = 1 - (_dx / _width).clamp(0.0, 1.0);
    if (!_active) {
      _active = true;
      widget.route.handleStartBackGesture(progress: progress);
    } else {
      widget.route.handleUpdateBackGestureProgress(progress: progress);
    }
  }

  void _end(double velocity) {
    if (!_active) return;
    _active = false;
    final route = widget.route;
    final commit = velocity >= kSwipeGestureVelocityThreshold
        ? true
        : velocity <= -kSwipeGestureVelocityThreshold
        ? false
        : _dx / _width >= kSwipeBackPositionThreshold;
    if (!commit) {
      route.handleCancelBackGesture();
      return;
    }
    // `handleCommitBackGesture`は閉じ始めてからアニメーションを最初
    // （全表示）へ巻き戻すため、指を離した位置から右へ消えるよう、自前で
    // popしてジェスチャーの終了を通知する。
    final navigator = route.navigator;
    final animation = route.animation;
    if (navigator == null || animation == null) return;
    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(onStatus);
      if (navigator.mounted) navigator.didStopUserGesture();
    }

    animation.addStatusListener(onStatus);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _dx = 0;
        _active = false;
      },
      onHorizontalDragUpdate: (details) {
        if (!widget.route.isCurrent) return;
        _dx += details.delta.dx;
        if (_dx > 0 || _active) _update();
      },
      onHorizontalDragCancel: () => _end(0),
      onHorizontalDragEnd: (details) => _end(details.primaryVelocity ?? 0),
      child: widget.child,
    );
  }
}
