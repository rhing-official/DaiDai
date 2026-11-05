import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// 押している間だけ少し縮み、離すと弾んで戻る（2026-11-05）。押下は`Listener`で拾う
/// ので、子の`InkWell`・`GestureDetector`のタップを邪魔しない。端末の「動きを減らす」
/// 設定では動かさない。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = pressScale,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down || !mounted) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: pressDuration,
        curve: _down ? Curves.easeOut : springCurve,
        child: widget.child,
      ),
    );
  }
}
