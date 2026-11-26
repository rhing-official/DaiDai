import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/chalk/chalk_theme.dart';
import 'liquid_chip_highlight.dart';
import 'nav_chip.dart';

/// 選ばれた項目の上（縦並びは右）へ出っ張る高さ。
const double kChalkBumpHeight = 16;

/// 選ばれた項目のチップを、出っ張りの方へ持ち上げる量。
const double kChalkLift = 10;

/// 帯の内側の余白。
const double _kPad = 12;

/// メニューチップの帯を、黒板にチョークで描いた1本の枠にする（2026-11-26、チョークスタイル）。
/// 枠は、選ばれた項目の位置だけ出っ張り、選択が移ると、出っ張りが次の項目へ滑る。
/// 「選択の動き」が「なし」なら、その場で移る。
///
/// [child]は、チップを並べたRow/Column。チップ同士の間は[kNavChipGap]、1つの大きさは
/// [kNavChipSize]として、出っ張りの位置を計算する。
class ChalkNavBar extends ConsumerWidget {
  const ChalkNavBar({
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
    final slide = ref.watch(selectionWaterMotionProvider);
    final target = (selectedIndex ?? -1).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: slide ? const Duration(milliseconds: 320) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, position, child) => CustomPaint(
        painter: _ChalkBarPainter(
          position: position,
          count: count,
          vertical: vertical,
          color: ChalkColors.chalk,
        ),
        child: child,
      ),
      child: Padding(padding: const EdgeInsets.all(_kPad), child: child),
    );
  }
}

class _ChalkBarPainter extends CustomPainter {
  _ChalkBarPainter({
    required this.position,
    required this.count,
    required this.vertical,
    required this.color,
  });

  /// 出っ張りの位置（項目の番号。小数は、滑っている途中）。負なら出っ張りなし。
  final double position;
  final int count;
  final bool vertical;
  final Color color;

  static const double _radius = 26;
  static const double _bumpHalf = 30;

  /// 枠の輪郭。横並びとして組み、縦並びは向きを回して使う。
  Path _outline(double length, double thickness, double bumpCenter) {
    final r = math.min(_radius, math.min(thickness, length) / 2);
    final bump = bumpCenter >= 0 && length > r * 2 + 1;
    final path = Path()..moveTo(r, 0);
    if (bump) {
      final left = (bumpCenter - _bumpHalf).clamp(r, length - r);
      final right = (bumpCenter + _bumpHalf).clamp(r, length - r);
      final mid = (left + right) / 2;
      path
        ..lineTo(left, 0)
        ..cubicTo(
          left + 14,
          0,
          mid - 18,
          -kChalkBumpHeight,
          mid,
          -kChalkBumpHeight,
        )
        ..cubicTo(mid + 18, -kChalkBumpHeight, right - 14, 0, right, 0);
    }
    path
      ..lineTo(length - r, 0)
      ..arcToPoint(Offset(length, r), radius: Radius.circular(r))
      ..lineTo(length, thickness - r)
      ..arcToPoint(Offset(length - r, thickness), radius: Radius.circular(r))
      ..lineTo(r, thickness)
      ..arcToPoint(Offset(0, thickness - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final length = vertical ? size.height : size.width;
    final thickness = vertical ? size.width : size.height;
    // 選ばれた項目の中心（枠の左端/上端から）。
    final center = position < 0
        ? -1.0
        : _kPad + position * (kNavChipSize + kNavChipGap) + kNavChipSize / 2;
    var path = _outline(length, thickness, center);
    if (vertical) {
      // 横並びの上辺が、右辺になるよう、時計回りに90度回す。
      path = path.transform(
        (Matrix4.identity()
              ..translateByDouble(size.width, 0, 0, 1)
              ..rotateZ(math.pi / 2))
            .storage,
      );
    }
    final rough = _roughen(path);
    // 粉っぽいにじみ、本線、かすれた2本目、の順に重ねる。
    canvas.drawPath(
      rough,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(
      rough,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.9),
    );
    canvas.drawPath(
      _roughen(path, shift: 1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.45),
    );
  }

  /// 線を、位置で決まる細かい揺れでずらして、手描きのチョークにする。揺れは、位置だけで
  /// 決まるので、出っ張りが滑っても、線がちらつかない。
  Path _roughen(Path path, {double shift = 0}) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      var first = true;
      for (var d = 0.0; d <= metric.length; d += 4) {
        final t = metric.getTangentForOffset(d);
        if (t == null) continue;
        final p = t.position;
        final nx = _noise(p.dx * 0.9 + shift * 31, p.dy * 0.9 + shift * 17);
        final ny = _noise(p.dy * 0.9 + 13 + shift * 29, p.dx * 0.9 + 7);
        final q = p + Offset(nx, ny) * 0.55;
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

  /// -1〜1の、位置から決まる擬似的な乱数。
  static double _noise(double x, double y) {
    final v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return (v - v.floorToDouble()) * 2 - 1;
  }

  @override
  bool shouldRepaint(covariant _ChalkBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.vertical != vertical ||
      old.color != color;
}

/// チップの帯。チョークスタイルは[ChalkNavBar]、他は水が流れ込む[LiquidChipStrip]。
class NavChipBand extends ConsumerWidget {
  const NavChipBand({
    required this.child,
    required this.entries,
    required this.selectedIndex,
    required this.vertical,
    super.key,
  });

  final Widget child;
  final List<LiquidChipEntry> entries;
  final int? selectedIndex;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.chalk) {
      return ChalkNavBar(
        count: entries.length,
        selectedIndex: selectedIndex,
        vertical: vertical,
        child: child,
      );
    }
    return LiquidChipStrip(
      entries: entries,
      selectedIndex: selectedIndex,
      vertical: vertical,
      child: child,
    );
  }
}
