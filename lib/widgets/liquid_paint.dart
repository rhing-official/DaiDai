import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'liquid_sim.dart';

/// 水の糸と水滴・飛沫を描く（2026-11-26）。縁から次の項目へ、放物線を描いて注ぐ。
/// 水滴は丸い粒（[square]の劇画は角のある破片）。
void paintLiquidStreamAndDrops(
  Canvas canvas,
  LiquidSim sim,
  Color fill, {
  bool square = false,
  bool streams = false,
}) {
  // 項目の間を流れる水の糸は描かない（2026-11-27、ユーザー指示）。水滴・飛沫は描く。
  final paint = Paint()..color = fill;
  // 流れ: 元の項目の縁から、太い帯になって、放物線を描いて次の項目へ注ぐ。元の項目の水が
  // 減るほど細くなり、元の側が離れると、途切れて水滴になる。
  for (final stream in streams ? sim.streams : const <LiquidStream>[]) {
    if (stream.t < 0) continue;
    final uh = Curves.easeOutCubic.transform(
      (stream.t / stream.headTime).clamp(0.0, 1.0),
    );
    // 元の項目が空になると、元の側が離れる。それまでは、縁につながったまま流れ続ける。
    final ut = Curves.easeInCubic.transform(
      (stream.tailAge / 0.3).clamp(0.0, 1.0),
    );
    if (uh - ut <= 0.01) continue;
    // 流れている水が多いほど太い（水が減ると細くなる）。
    final body = stream.width * (0.4 + 0.6 * stream.flowNow.clamp(0.0, 1.0));
    final endFade = 1 - 0.55 * (stream.tailAge / 0.34).clamp(0.0, 1.0);
    const n = 28;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var k = 0; k <= n; k++) {
      final f = k / n;
      final u = ut + (uh - ut) * f;
      final p = stream.at(u);
      final v = stream.velocityAt(u);
      final len = v.distance == 0 ? 1.0 : v.distance;
      final nrm = Offset(-v.dy / len, v.dx / len);
      // 縁のつけ根は広く（水が溢れる膜）、落ちるほど少し細くなり、着地の手前で広がる。
      final root = 1.0 + 0.5 * math.exp(-f * 6);
      final landing =
          1.0 + 0.35 * math.exp(-(1 - f) * 7) * (uh >= 0.95 ? 1 : uh);
      // 流れに沿って動く、ゆるい太さの揺れ（水が流れている動き）。
      final ripple = 1 + 0.12 * math.sin(f * 11 - stream.t * 26);
      // 先端だけ丸く細める。
      final head = f > 0.9 && uh < 1 ? math.sqrt((1 - f) / 0.1) : 1.0;
      final w = body * 0.5 * root * landing * ripple * head * endFade;
      left.add(p + nrm * w);
      right.add(p - nrm * w);
    }
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    // 先端の丸み。
    if (uh < 1) {
      canvas.drawCircle(stream.at(uh), body * 0.5 * 0.9 * endFade, paint);
    }
  }

  // 水滴・飛沫。
  for (final d in sim.drops) {
    final life = (d.age / d.life).clamp(0.0, 1.0);
    final radius = d.radius * (1 - 0.35 * life);
    final fade = life < 0.7 ? 1.0 : (1 - (life - 0.7) / 0.3);
    final dropPaint = Paint()
      ..color = fill.withValues(alpha: (fill.a * fade).clamp(0.0, 1.0));
    if (square) {
      final a = d.age * 9 + d.life * 5;
      final shard = Path()
        ..moveTo(
          d.pos.dx + math.cos(a) * radius * 1.7,
          d.pos.dy + math.sin(a) * radius * 1.7,
        )
        ..lineTo(
          d.pos.dx + math.cos(a + 2.4) * radius,
          d.pos.dy + math.sin(a + 2.4) * radius,
        )
        ..lineTo(
          d.pos.dx + math.cos(a + 3.9) * radius,
          d.pos.dy + math.sin(a + 3.9) * radius,
        );
      shard.close();
      canvas.drawPath(shard, dropPaint);
    } else {
      canvas.drawCircle(d.pos, radius, dropPaint);
    }
  }
}
