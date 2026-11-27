import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nav_chip.dart';

/// 帯の内側の余白。
const double _kPad = 6;

/// メニューチップの帯を、紙にへこんだ帯にする（2026-11-26、生成りスタイル）。選ばれた項目には、
/// アクセントカラーの丸い印が重なり、選択が移ると滑る。「選択の動き」が
/// 「なし」なら、その場で移る。柔らかい内側の影とわずかな浮きは、このスタイルのこの帯だけの例外。
///
/// [child]は、チップを並べたRow/Column。チップ同士の間は[kNavChipGap]、1つの大きさは
/// [kNavChipSize]として、印の位置を計算する。
class KinariNavBar extends ConsumerWidget {
  const KinariNavBar({
    required this.child,
    required this.count,
    required this.selectedIndex,
    required this.vertical,
    super.key,
  });

  final Widget child;
  final int count;
  final int? selectedIndex;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = (selectedIndex ?? -1).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, position, child) => RingBarPosition(
        position: position,
        child: CustomPaint(
          painter: _KinariBarPainter(
            position: position,
            vertical: vertical,
            base: scheme.surface,
            pill: scheme.primary,
          ),
          child: child,
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(_kPad), child: child),
    );
  }
}

class _KinariBarPainter extends CustomPainter {
  _KinariBarPainter({
    required this.position,
    required this.vertical,
    required this.base,
    required this.pill,
  });

  /// 印の位置（項目の番号。小数は、滑っている途中）。負なら印なし。
  final double position;
  final bool vertical;
  final Color base;
  final Color pill;

  static const double _radius = 28;

  @override
  void paint(Canvas canvas, Size size) {
    // 横並びとして描き、縦並びは、同じ描画を、90度回して使う（影の向きも共通）。
    final length = vertical ? size.height : size.width;
    final thickness = vertical ? size.width : size.height;
    canvas.save();
    if (vertical) {
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
    }
    final r = math.min(_radius, thickness / 2);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, length, thickness),
      Radius.circular(r),
    );
    // へこんだ帯: 紙より少し濃い色に、内側の影（上）と明かり（下）。
    // 画面では、どちらの向きでも、左上の縁の内側に影が落ちる（回した分を打ち消した向き）。
    final shadowOffset = vertical ? const Offset(3, -2) : const Offset(2, 3);
    paintKinariInset(canvas, rrect, base, shadowOffset);

    if (position >= 0) {
      final center =
          _kPad + position * (kNavChipSize + kNavChipGap) + kNavChipSize / 2;
      // 正円（チップの丸より少し小さく、帯の厚みに収まる大きさ）。
      final h = math.min(kNavChipSize - 6, thickness - 12);
      final rect = Rect.fromCenter(
        center: Offset(center, thickness / 2),
        width: h,
        height: h,
      );
      // 囲んだ範囲は、帯よりさらにへこませ、アクセントカラーで塗り潰す（2026-11-27。以前は
      // 塗らず、線で囲むだけだった）。アクセントの面が、へこんだ穴に嵌まって見える。
      final circle = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
      paintKinariInset(canvas, circle, pill, shadowOffset * 1.3, depth: 2.4);
      // 縁は、同じ色の線で囲む。
      canvas.drawRRect(
        circle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = pill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KinariBarPainter old) =>
      old.position != position ||
      old.vertical != vertical ||
      old.base != base ||
      old.pill != pill;
}

/// へこみ（紙より少し濃い面に、内側の影と明かり）を描く。[offset]は、影の向き。
void paintKinariInset(
  Canvas canvas,
  RRect rrect,
  Color base,
  Offset offset, {
  double depth = 1,
  double light = 1,
}) {
  canvas.drawRRect(
    rrect,
    Paint()..color = Color.lerp(base, Colors.black, 0.04)!,
  );
  paintKinariInsetShadows(canvas, rrect, offset, depth: depth, light: light);
}

/// へこみの内側の影と明かりだけを描く（面は塗らない）。中身の前に重ねて描く用。
void paintKinariInsetShadows(
  Canvas canvas,
  RRect rrect,
  Offset offset, {
  double depth = 1,
  double light = 1,
}) {
  void inner(Offset o, Color color) {
    canvas.save();
    canvas.clipRRect(rrect);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rrect.outerRect.inflate(60))
      ..addRRect(rrect.shift(o));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.restore();
  }

  inner(offset, Colors.black.withValues(alpha: (0.2 * depth).clamp(0.0, 1.0)));
  inner(
    -offset,
    Colors.white.withValues(alpha: (0.7 * depth * light).clamp(0.0, 1.0)),
  );
}

/// 選択色の塗りを、へこんで見せる（生成り）。塗りのある所にだけ、チップの丸に沿った内側の影と
/// 明かりを重ねる（`srcATop`なので、塗りの外には出ない）。塗りを描いた層の中で、アイコンを
/// 描き直す前に呼ぶ。
void paintKinariRecess(Canvas canvas, Rect bounds, Iterable<Rect> chips) {
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
  for (final r in chips) {
    paintKinariInsetShadows(
      canvas,
      RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)),
      const Offset(2, 3),
      depth: 2.2,
      // 色の付いた面の上では、白い明かりを弱くする（強いと、塗りが白くかすんで見える）。
      light: 0.3,
    );
  }
  canvas.restore();
}

/// わずかに浮いた印（丸い角）を描く。
void paintKinariPill(Canvas canvas, Rect rect, Color pill) {
  final pillRRect = RRect.fromRectAndRadius(
    rect,
    Radius.circular(rect.shortestSide / 2),
  );
  // わずかな浮き: 印の下に、柔らかい影。
  canvas.drawRRect(
    pillRRect.shift(const Offset(0, 2)),
    Paint()
      ..color = Color.lerp(pill, Colors.black, 0.45)!.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.drawRRect(pillRRect, Paint()..color = pill);
  canvas.save();
  canvas.clipRRect(pillRRect);
  // 上の明かり。
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0.1),
        ],
      ).createShader(rect),
  );
  canvas.restore();
}

/// 分けた（液体・なし）生成りスタイルのメニューチップ1つ分の、へこんだ丸。[fill]があれば（なしで選択中）、
/// 印を重ねる。
class KinariInsetChipPainter extends CustomPainter {
  KinariInsetChipPainter({required this.base, this.fill});

  final Color base;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide / 2),
    );
    paintKinariInset(canvas, rrect, base, const Offset(2, 3));
    // 選択中は、アクセントの塗りをへこませる（浮かせない）。
    final f = fill;
    if (f != null) {
      final inner = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(3),
        Radius.circular(size.shortestSide / 2),
      );
      canvas.drawRRect(inner, Paint()..color = f);
      paintKinariInsetShadows(canvas, inner, const Offset(2, 3), depth: 2.2);
    }
  }

  @override
  bool shouldRepaint(covariant KinariInsetChipPainter old) =>
      old.base != base || old.fill != fill;
}

/// 大きなブロック（一覧の背景）の、へこんだ面。メニューチップの帯と同じ描き方。
class KinariInsetBlockPainter extends CustomPainter {
  KinariInsetBlockPainter(this.base, this.radius);

  final Color base;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    paintKinariInset(
      canvas,
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      base,
      const Offset(2, 3),
    );
  }

  @override
  bool shouldRepaint(covariant KinariInsetBlockPainter old) =>
      old.base != base || old.radius != radius;
}
