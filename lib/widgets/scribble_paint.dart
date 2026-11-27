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

  /// [progress]まで進んだ分の塗りを、切り抜きの形（[Path]）で返す（2026-11-28）。
  /// [partial]の線を太らせたものと、ほぼ同じ形。往復の各行を丸い端の帯にし、行の間は、
  /// 折り返しの端の帯でつなぐ。描画の層を途中で切り替える子（透明度・変形など）でも
  /// 壊れないよう、`saveLayer`のマスクではなく、切り抜きで使う為に作った。
  static Path clipPath(Rect rect, double progress) {
    final rows = rowsFor(rect.size);
    final pen = penWidthFor(rect.size, rows);
    final radius = Radius.circular(pen / 2);
    final left = rect.left - pen / 3;
    final right = rect.right + pen / 3;
    final top = rect.top + pen / 3;
    final bottom = rect.bottom - pen / 3;
    final rowLength = right - left;
    final gap = rows == 1 ? 0.0 : (bottom - top) / (rows - 1);
    final total = rows * rowLength + (rows - 1) * gap;
    var remaining = progress.clamp(0.0, 1.0) * total;
    final path = Path();
    for (var r = 0; r < rows && remaining > 0; r++) {
      final y = rows == 1 ? rect.center.dy : bottom - gap * r;
      final jitter = math.sin(r * 12.9898 + rect.width * 0.37) * 1.6;
      final length = math.min(remaining, rowLength);
      final toRight = r.isEven;
      final start = toRight ? left : right;
      final end = toRight ? left + length : right - length;
      path.addRRect(
        RRect.fromLTRBR(
          math.min(start, end) - pen / 2,
          y + jitter - pen / 2,
          math.max(start, end) + pen / 2,
          y + jitter + pen / 2,
          radius,
        ),
      );
      remaining -= length;
      // 折り返しの端で、次の行へ上がる。
      if (remaining > 0 && r < rows - 1) {
        path.addRect(
          Rect.fromLTRB(end - pen / 2, y - gap, end + pen / 2, y + jitter),
        );
        remaining -= gap;
      }
    }
    return path;
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

/// [ScribbleReveal]と同じ見え方を、切り抜きで作る版（2026-11-28）。画面遷移・ダイアログ用。
///
/// [ScribbleReveal]は、子を`saveLayer`に描いてからマスクを重ねる。子の中で透明度・
/// 変形などが描画の層を切り替えると、最初に取った描き先が使えなくなり、例外になる。
/// この版は、ペンの形の切り抜き（[ScribblePen.clipPath]）で子を描くので、そうならない。
class ScribbleLayerReveal extends SingleChildRenderObjectWidget {
  const ScribbleLayerReveal({
    required this.progress,
    required super.child,
    this.fitContent = false,
    super.key,
  });

  final double progress;

  /// 真の時、ペンで塗る範囲を、自分の大きさ全体ではなく、中身の見える箱の大きさにする。
  /// ダイアログ・ポップアップは、画面全体に置かれた層の中に、小さな箱が有る。画面全体を
  /// 塗ると、箱が現れる時機がずれ、ペンも太くなる。
  final bool fitContent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScribbleLayerReveal(progress, fitContent);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScribbleLayerReveal renderObject,
  ) {
    renderObject
      ..progress = progress
      ..fitContent = fitContent;
  }
}

class _RenderScribbleLayerReveal extends RenderProxyBox {
  _RenderScribbleLayerReveal(this._progress, this._fitContent);

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  bool _fitContent;
  set fitContent(bool value) {
    if (value == _fitContent) return;
    _fitContent = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipPathLayer> _clipLayer = LayerHandle<ClipPathLayer>();

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  /// 配置だけをする層（余白・中央寄せ・制約・透明度など）をたどって、見える箱を探し、
  /// 自分の座標での範囲を返す。見つからなければ自分の全体。
  Rect _contentRect() {
    RenderBox? node = child;
    while (node != null) {
      if (node is RenderDecoratedBox ||
          node is RenderPhysicalModel ||
          node is RenderPhysicalShape ||
          node is RenderClipRRect ||
          node is RenderClipPath ||
          node is RenderClipRect ||
          node is RenderClipOval ||
          node is RenderCustomPaint) {
        break;
      }
      RenderBox? next;
      if (node is RenderProxyBox) {
        next = node.child;
      } else if (node is RenderShiftedBox) {
        next = node.child;
      }
      if (next == null) break;
      node = next;
    }
    if (node == null || !node.hasSize) return Offset.zero & size;
    return node.localToGlobal(Offset.zero, ancestor: this) & node.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_progress >= 1) {
      _clipLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    if (_progress <= 0) {
      _clipLayer.layer = null;
      return;
    }
    // 箱に合わせる時は、箱の外のはみ出し（影など）が、ペンの太さの分だけ残るようにする。
    final penRect = _fitContent
        ? _contentRect().inflate(12)
        : Offset.zero & size;
    _clipLayer.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      ScribblePen.clipPath(penRect, _progress),
      (context, offset) => context.paintChild(child, offset),
      clipBehavior: Clip.antiAlias,
      oldLayer: _clipLayer.layer,
    );
  }
}
