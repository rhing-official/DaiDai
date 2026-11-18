import 'package:flutter/material.dart';

/// 呼び出し中（まだ繋がっていない間）に、相手のアイコンの周りから同心円状に広がる、
/// アクセントカラーの線（2026-11-18）。[child]（アイコン）の外側へ、3本の輪が時間差で広がって
/// 薄くなる。[active]がfalseなら描かず、アニメーションも止める。
class CallRingRipple extends StatefulWidget {
  const CallRingRipple({
    required this.child,
    required this.radius,
    this.active = true,
    this.color,
    this.reachFactor = 1.9,
    super.key,
  });

  final Widget child;

  /// アイコンの半径。輪はここから外へ広がる。
  final double radius;
  final bool active;

  /// 輪の色。未指定は`colorScheme.primary`（アクセントカラー）。
  final Color? color;

  /// 輪が広がりきった時の半径の、アイコンの半径に対する倍率。狭い所（着信バナー等）では小さくする。
  final double reachFactor;

  @override
  State<CallRingRipple> createState() => _CallRingRippleState();
}

class _CallRingRippleState extends State<CallRingRipple>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(CallRingRipple old) {
    super.didUpdateWidget(old);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    // 広がりきった時の輪の半径。輪はアイコンの外側（レイアウトの外）に描くので、アイコンの
    // 位置・大きさ（周りの並び）は波紋の有無で変わらない。
    final reach = widget.radius * widget.reachFactor;
    final overflow = reach - widget.radius;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -overflow,
          right: -overflow,
          top: -overflow,
          bottom: -overflow,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _RipplePainter(
                  progress: _controller.value,
                  color: color,
                  innerRadius: widget.radius,
                  outerRadius: reach,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.progress,
    required this.color,
    required this.innerRadius,
    required this.outerRadius,
  });

  final double progress;
  final Color color;
  final double innerRadius;
  final double outerRadius;

  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < _rings; i++) {
      // 輪ごとに周期の1/3ずつずらす。
      final t = (progress + i / _rings) % 1.0;
      final radius = innerRadius + (outerRadius - innerRadius) * t;
      final opacity = (1 - t) * 0.9;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress || old.color != color;
}

/// 相手のアイコンに、呼び出し中の波紋を付ける共通の部品（2026-11-18）。判定を1か所にまとめ、
/// スマホの通話画面（`CallScreen`）・PC・Webの通話画面（`CallOverlayView`）・ミニ表示・着信バナーで
/// 同じ見た目にする。[ringing]がtrue（相手側で、まだ繋がっていない間）のあいだだけ波紋を出す。
/// 輪は周りの配置に影響しない（アイコンの外側に描く）。
class CallRingingAvatar extends StatelessWidget {
  const CallRingingAvatar({
    required this.ringing,
    required this.radius,
    required this.avatar,
    this.reachFactor = 1.9,
    super.key,
  });

  final bool ringing;
  final double radius;
  final Widget avatar;
  final double reachFactor;

  @override
  Widget build(BuildContext context) {
    return CallRingRipple(
      active: ringing,
      radius: radius,
      reachFactor: reachFactor,
      child: avatar,
    );
  }
}
