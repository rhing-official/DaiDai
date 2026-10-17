import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 手描きの丸の経路（2026-10-17追加）。[rect]を囲む楕円を、**始点と終点を少し
/// 重ねて**（約[turns]周）描き、半径を滑らかにゆらして手描きらしくする。揺らぎは
/// [seed]で決まり、同じ引数なら必ず同じ形になる（再描画のたびに形が変わらない）。
Path handDrawnCirclePath(
  Rect rect, {
  int seed = 1,
  double padding = 14,
  double turns = 1.12,
}) {
  // Webの`nextInt`は上限が2^32未満のためseedを収める（`gekiga_shapes.dart`と同じ注意）。
  final random = math.Random(seed.abs() % 0x7fffffff);
  final center = rect.center;
  final rx = rect.width / 2 + padding;
  final ry = rect.height / 2 + padding;
  final phase1 = random.nextDouble() * math.pi * 2;
  final phase2 = random.nextDouble() * math.pi * 2;
  // 描き始めの角度も少しばらつかせる（真上から少し左）。
  final start = -math.pi / 2 - 0.25 - random.nextDouble() * 0.4;
  const count = 96;
  final points = <Offset>[];
  for (var i = 0; i <= count; i++) {
    final t = i / count;
    final theta = start + math.pi * 2 * turns * t;
    // 周期の違う2つの波＋徐々に外へ広がる渦（終点が始点にぴったり重ならない）。
    final wobble =
        1 +
        0.035 * math.sin(2 * theta + phase1) +
        0.02 * math.sin(3 * theta + phase2) +
        0.05 * (t - 0.5);
    points.add(
      Offset(
        center.dx + rx * wobble * math.cos(theta),
        center.dy + ry * wobble * math.sin(theta),
      ),
    );
  }
  // 点列を、隣り合う点の中点を通す2次ベジェでなめらかにつなぐ。
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset(
      (points[i].dx + points[i + 1].dx) / 2,
      (points[i].dy + points[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// [path]を先頭から[progress]（0〜1）の長さまで切り出す。
Path partialPath(Path path, double progress) {
  final clamped = progress.clamp(0.0, 1.0);
  final result = Path();
  for (final metric in path.computeMetrics()) {
    result.addPath(metric.extractPath(0, metric.length * clamped), Offset.zero);
  }
  return result;
}

/// 1軸分の拡縮と平行移動。`x' = x * scale + offset`。
typedef AxisFit = ({double scale, double offset});

/// [content]が[bounds]（から[margin]を引いた内側）に収まるよう、はみ出す側だけを
/// 縮める変換を軸ごとに返す。はみ出していない側の端は動かさない。
({AxisFit dx, AxisFit dy}) fitAxes(
  Rect content,
  Rect bounds, {
  double margin = 0,
}) {
  AxisFit one(double lo, double hi, double minLo, double maxHi) {
    final newLo = lo < minLo ? minLo : lo;
    final newHi = hi > maxHi ? maxHi : hi;
    if (hi <= lo || (newLo == lo && newHi == hi)) {
      return (scale: 1, offset: 0);
    }
    final scale = (newHi - newLo) / (hi - lo);
    return (scale: scale, offset: newLo - lo * scale);
  }

  return (
    dx: one(
      content.left,
      content.right,
      bounds.left + margin,
      bounds.right - margin,
    ),
    dy: one(
      content.top,
      content.bottom,
      bounds.top + margin,
      bounds.bottom - margin,
    ),
  );
}

/// 手描きの丸を、[progress]に応じて描き進める（0〜1）。線は2重（濃い線と、
/// 少しずれた薄い線）で、白い縁取りを付けて明暗どちらの背景でも見えるようにする。
class HandDrawnCirclePainter extends CustomPainter {
  const HandDrawnCirclePainter({
    required this.rect,
    required this.progress,
    this.seed = 1,
    this.color = const Color(0xFFE53935),
  });

  final Rect rect;
  final double progress;
  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    // 目印が画面の端にあっても、丸（と縁取り）が画面からはみ出さないようにする。
    // はみ出す側だけを内側へ縮める（丸は少し楕円になるが、目印は囲んだまま）。
    final full = handDrawnCirclePath(rect, seed: seed)
        .getBounds()
        .expandToInclude(
          handDrawnCirclePath(
            rect,
            seed: seed + 7,
            padding: 18,
            turns: 1.0,
          ).getBounds(),
        );
    final fit = fitAxes(full, Offset.zero & size, margin: 6);
    canvas
      ..save()
      ..translate(fit.dx.offset, fit.dy.offset)
      ..scale(fit.dx.scale, fit.dy.scale);
    final main = partialPath(handDrawnCirclePath(rect, seed: seed), progress);
    final second = partialPath(
      handDrawnCirclePath(rect, seed: seed + 7, padding: 18, turns: 1.0),
      // 2本目は少し遅れて描き始める。
      ((progress - 0.15) / 0.85).clamp(0.0, 1.0),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.9);
    final strong = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.5
      ..color = color;
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.55);
    canvas
      ..drawPath(main, outline)
      ..drawPath(second, faint)
      ..drawPath(main, strong)
      ..restore();
  }

  @override
  bool shouldRepaint(HandDrawnCirclePainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.progress != progress ||
      oldDelegate.seed != seed ||
      oldDelegate.color != color;
}
