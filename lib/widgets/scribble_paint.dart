import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// ペンで往復して塗る、「描き」の描画部品（2026-11-26）。
///
/// 長方形[rect]を、太いペンで、左下から右上へ向かって、下から上へ横に往復しながら塗りつぶす経路。[progress]（0〜1）まで
/// 進んだ分だけの経路を返す。先は丸く、縁は少し荒い（位置から決まる揺れ）。1の時は、全体を覆う。
class ScribblePen {
  ScribblePen._();

  /// 往復の回数。小さい項目は3、大きい項目は、高さに合わせて5まで。
  /// 往復は、奇数回（3か5）。左下から始めて、右上で終わる為。
  static int rowsFor(Size size) => size.height < 80 ? 3 : 5;

  static double penWidthFor(Size size, int rows) =>
      (size.height / rows) * 1.45 + 2;

  /// 全体の経路（進み具合の前の、全ての往復）。
  static Path fullPath(Rect rect, int rows) {
    final pen = penWidthFor(rect.size, rows);
    final path = Path();
    final left = rect.left - pen / 3;
    final right = rect.right + pen / 3;
    final top = rect.top + pen / 3;
    final bottom = rect.bottom - pen / 3;
    for (var r = 0; r < rows; r++) {
      // 下の行から上の行へ（左下から右上へ向かって描く）。
      final y = rows == 1
          ? rect.center.dy
          : bottom - (bottom - top) * r / (rows - 1);
      // 位置から決まる、小さな揺れ。
      final jitter = math.sin(r * 12.9898 + rect.width * 0.37) * 1.6;
      final toRight = r.isEven;
      final x0 = toRight ? left : right;
      final x1 = toRight ? right : left;
      if (r == 0) {
        path.moveTo(x0, y + jitter);
      } else {
        path.lineTo(x0, y + jitter);
      }
      path.lineTo(x1, y - jitter);
    }
    return path;
  }

  /// [progress]まで進んだ経路。
  static Path partial(Rect rect, int rows, double progress) {
    final full = fullPath(rect, rows);
    if (progress >= 1) return full;
    final out = Path();
    for (final m in full.computeMetrics()) {
      out.addPath(
        m.extractPath(0, m.length * progress.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }
    return out;
  }

  /// [rect]の中を、[progress]まで、[color]のペンで塗る。[clip]があれば、その形の中だけ。
  static void paint(
    Canvas canvas,
    Rect rect,
    Color color,
    double progress, {
    Path? clip,
  }) {
    if (progress <= 0) return;
    canvas.save();
    if (clip != null) canvas.clipPath(clip);
    if (progress >= 1) {
      // 塗り終わりは、一様な塗り。
      canvas.drawRect(rect.inflate(2), Paint()..color = color);
      canvas.restore();
      return;
    }
    final rows = rowsFor(rect.size);
    canvas.drawPath(
      partial(rect, rows, progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = penWidthFor(rect.size, rows)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }
}

/// [child]（選ばれた見た目）を、ペンで塗った所だけ見せる。塗っていない所は、後ろ（選ばれていない見た目）が見える。
class ScribbleReveal extends SingleChildRenderObjectWidget {
  const ScribbleReveal({
    required this.progress,
    required super.child,
    super.key,
  });

  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScribbleReveal(progress);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScribbleReveal renderObject,
  ) {
    renderObject.progress = progress;
  }
}

class _RenderScribbleReveal extends RenderProxyBox {
  _RenderScribbleReveal(this._progress);

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_progress >= 1) {
      context.paintChild(child, offset);
      return;
    }
    if (_progress <= 0) return;
    final rect = offset & size;
    final canvas = context.canvas;
    canvas.saveLayer(rect.inflate(2), Paint());
    context.paintChild(child, offset);
    // マスク: ペンで塗った所だけ残す。
    canvas.saveLayer(rect.inflate(2), Paint()..blendMode = BlendMode.dstIn);
    ScribblePen.paint(canvas, rect, Colors.black, _progress);
    canvas.restore();
    canvas.restore();
  }
}
