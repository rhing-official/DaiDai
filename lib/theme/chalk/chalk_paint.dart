import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// チョークの描き方の共通部品（2026-11-26）。線は位置だけで決まる揺れ・かすれを持ち、動かしても
/// ちらつかない。
class ChalkPaint {
  ChalkPaint._();

  /// -1〜1の、位置から決まる擬似的な乱数。
  static double noise(double x, double y) {
    final v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return (v - v.floorToDouble()) * 2 - 1;
  }

  /// 塗りを、チョークで塗ったような質感にする。[area]の中に、粉の抜け（細かい点）と、斜めのかすれ
  /// （チョークを寝かせてこすった跡）を、塗りの透けとして彫る。`saveLayer`の中で、塗りを描いた
  /// 後に呼ぶ。位置から決まる乱数なので、動かしてもちらつかない。
  static void punchGrain(Canvas canvas, Rect area) {
    if (area.isEmpty) return;
    final random = math.Random(5);
    final dots = <Offset>[];
    final n = (area.width * area.height / 9).clamp(200, 9000).toInt();
    for (var i = 0; i < n; i++) {
      dots.add(
        Offset(
          area.left + random.nextDouble() * area.width,
          area.top + random.nextDouble() * area.height,
        ),
      );
    }
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0x73000000),
    );
    final streaks = Path();
    final m = (area.width * area.height / 700).clamp(30, 1200).toInt();
    for (var i = 0; i < m; i++) {
      final x = area.left + random.nextDouble() * area.width;
      final y = area.top + random.nextDouble() * area.height;
      final len = 7 + random.nextDouble() * 16;
      final a = -0.62 + (random.nextDouble() - 0.5) * 0.3;
      streaks
        ..moveTo(x, y)
        ..lineTo(x + math.cos(a) * len, y + math.sin(a) * len);
    }
    canvas.drawPath(
      streaks,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0x59000000),
    );
  }

  /// [path]を[color]で、チョークで塗ったような質感で塗る。
  static void fillPath(Canvas canvas, Path path, Color color) {
    final bounds = path.getBounds().inflate(2);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(path, Paint()..color = color);
    punchGrain(canvas, bounds);
    canvas.restore();
  }

  /// 線を、細かい揺れでずらした折れ線にする。[amount]は揺れの大きさ（px）。
  static Path roughen(Path path, {double shift = 0, double amount = 0.7}) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      var first = true;
      for (var d = 0.0; d <= metric.length; d += 4) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        final p = t.position;
        final nx = noise(p.dx * 0.9 + shift * 31, p.dy * 0.9 + shift * 17);
        final ny = noise(p.dy * 0.9 + 13 + shift * 29, p.dx * 0.9 + 7);
        // ゆっくりした、大きな波も足す（手で引いた線のうねり）。
        final wave = math.sin(d / 37 + shift * 3) * amount * 0.5;
        final n = t.vector;
        final q = p + Offset(nx, ny) * amount + Offset(-n.dy, n.dx) * wave;
        if (first) {
          out.moveTo(q.dx, q.dy);
          first = false;
        } else {
          out.lineTo(q.dx, q.dy);
        }
      }
    }
    return out;
  }

  /// チョークで引いた線。粉のにじみ、かすれた本線（濃さの違う3本の粒）、飛び散った粉の点を重ねる。
  static void stroke(
    Canvas canvas,
    Path path,
    Color color, {
    double width = 2.2,
    double seed = 0,
  }) {
    final rough = roughen(path, shift: seed);
    // 粉のにじみ。
    canvas.drawPath(
      rough,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2
        ..color = color.withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width),
    );
    // 本線は、短く区切って、濃さを3段階に振り分ける。所々に、かすれて抜けた所を作る。
    final strong = Path();
    final mid = Path();
    final weak = Path();
    final specks = <Offset>[];
    for (final metric in rough.computeMetrics()) {
      const step = 3.0;
      for (var d = 0.0; d < metric.length; d += step) {
        final a = metric.getTangentForOffset(d);
        final b = metric.getTangentForOffset(math.min(d + step, metric.length));
        if (a == null || b == null) continue;
        final n = noise(a.position.dx * 1.7 + seed, a.position.dy * 1.7);
        final target = n > 0.82
            ? null
            : (n > 0.35 ? weak : (n > -0.35 ? mid : strong));
        if (target == null) {
          // 抜けた所には、粉の点だけを残す。
          specks.add(a.position);
          continue;
        }
        target
          ..moveTo(a.position.dx, a.position.dy)
          ..lineTo(b.position.dx, b.position.dy);
        if (n < -0.6) {
          // 線の脇へ、粉が飛ぶ。
          final v = a.vector;
          final side = noise(a.position.dy, a.position.dx) > 0 ? 1.0 : -1.0;
          specks.add(
            a.position + Offset(-v.dy, v.dx) * side * (width * 0.9 + 0.8),
          );
        }
      }
    }
    Paint line(double alpha, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: alpha);
    canvas.drawPath(weak, line(0.42, width * 0.8));
    canvas.drawPath(mid, line(0.72, width * 0.95));
    canvas.drawPath(strong, line(0.95, width));
    canvas.drawPoints(
      PointMode.points,
      specks,
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.5),
    );
  }
}

/// チョークで囲んだ面の形。面の塗りは`Material`が描き、この形は縁だけをチョークで描く
/// （影は無い）。カード・ダイアログ・メニュー・ボタンの形に使う。
class ChalkShapeBorder extends OutlinedBorder {
  const ChalkShapeBorder({
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.color = const Color(0xFFF1EFE3),
    this.width = 1.8,
    super.side = BorderSide.none,
  });

  final BorderRadius borderRadius;
  final Color color;
  final double width;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  OutlinedBorder copyWith({BorderSide? side}) => ChalkShapeBorder(
    borderRadius: borderRadius,
    color: color,
    width: width,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect).deflate(width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final path = Path()
      ..addRRect(borderRadius.toRRect(rect.deflate(width / 2)));
    // 位置を種にして、面ごとに線の揺れ方を変える。
    ChalkPaint.stroke(
      canvas,
      path,
      color,
      width: width,
      seed: (rect.left * 0.37 + rect.top * 0.91) % 50,
    );
  }
}

/// 黒板の上に、消し残したチョークの粉と、細かい粒を薄く重ねる層。タッチは通さない。
/// 大きさが変わった時だけ描き直す。
class ChalkBoardDust extends StatelessWidget {
  const ChalkBoardDust({this.color = const Color(0xFFF1EFE3), super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _DustPainter(color), size: Size.infinite),
    ),
  );
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.chalk);

  final Color chalk;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(7);
    // 黒板消しで拭いた、大きな白いかすみ。
    final area = size.width * size.height;
    final smudges = (area / 60000).clamp(6, 40).toInt();
    for (var i = 0; i < smudges; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 50 + random.nextDouble() * 140;
      final stretch = 0.35 + random.nextDouble() * 0.5;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(random.nextDouble() * math.pi);
      canvas.scale(1, stretch);
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              chalk.withValues(alpha: 0.035 + random.nextDouble() * 0.03),
              chalk.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
      );
      canvas.restore();
    }
    // 細かい粉の粒。
    final dots = (area / 900).clamp(200, 2500).toInt();
    final points = <Offset>[
      for (var i = 0; i < dots; i++)
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = chalk.withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => old.chalk != chalk;
}

/// チョークで囲んだ箱の装飾（`Container`・`DecoratedBox`用）。塗りの上に、チョークの縁を描く。
/// [BoxDecoration]として使えるよう、その子クラスにしてある。
class ChalkBoxDecoration extends BoxDecoration {
  const ChalkBoxDecoration({
    super.color,
    BorderRadius super.borderRadius = const BorderRadius.all(
      Radius.circular(14),
    ),
    this.lineColor = const Color(0xFFF1EFE3),
    this.lineWidth = 1.8,
  });

  final Color lineColor;
  final double lineWidth;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ChalkBoxPainter(this);
}

class _ChalkBoxPainter extends BoxPainter {
  _ChalkBoxPainter(this.decoration);

  final ChalkBoxDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = offset & size;
    final radius =
        (decoration.borderRadius ?? BorderRadius.zero) as BorderRadius;
    final fill = decoration.color;
    if (fill != null) {
      canvas.drawRRect(radius.toRRect(rect), Paint()..color = fill);
    }
    ChalkPaint.stroke(
      canvas,
      Path()..addRRect(radius.toRRect(rect.deflate(decoration.lineWidth / 2))),
      decoration.lineColor,
      width: decoration.lineWidth,
      seed: (rect.left * 0.37 + rect.top * 0.91) % 50,
    );
  }
}

/// 入力欄の縁。チョークで引いた線で、角丸の枠を描く。
class ChalkInputBorder extends InputBorder {
  const ChalkInputBorder({
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color = const Color(0xFFF1EFE3),
    this.width = 1.6,
  }) : super(borderSide: BorderSide.none);

  final BorderRadius borderRadius;
  final Color color;
  final double width;

  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  InputBorder copyWith({BorderSide? borderSide}) => this;

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect).deflate(width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    // ラベルが浮く時の切り欠きは、塗りが無いので、線をそのまま描く。
    ChalkPaint.stroke(
      canvas,
      Path()..addRRect(borderRadius.toRRect(rect.deflate(width / 2))),
      color,
      width: width,
      seed: (rect.left * 0.37 + rect.top * 0.91) % 50,
    );
  }
}
