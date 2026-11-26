import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/chalk/chalk_paint.dart';
import 'liquid_chip_highlight.dart';
import 'nav_chip.dart';

/// 帯の内側の余白。
const double _kPad = 12;

/// メニューチップの帯を、黒板にチョークで描いた1本の枠にする（2026-11-26、チョークスタイル）。
/// 選ばれた項目は、アクセントカラー（黄色のチョーク）の輪で囲み、選択が移ると、輪が次の項目へ滑る。
/// 「選択の動き」が「なし」なら、その場で移る。
///
/// [child]は、チップを並べたRow/Column。チップ同士の間は[kNavChipGap]、1つの大きさは
/// [kNavChipSize]として、輪の位置を計算する。
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
          color: Theme.of(context).colorScheme.onSurface,
          ringColor: Theme.of(context).colorScheme.primary,
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
    required this.ringColor,
  });

  /// 出っ張りの位置（項目の番号。小数は、滑っている途中）。負なら出っ張りなし。
  final double position;
  final int count;
  final bool vertical;
  final Color color;
  final Color ringColor;

  static const double _radius = 26;

  /// 枠の輪郭。横並びとして組み、縦並びは向きを回して使う。
  Path _outline(double length, double thickness) {
    final r = math.min(_radius, math.min(thickness, length) / 2);
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, length, thickness),
        Radius.circular(r),
      ),
    );
  }

  /// 選ばれた項目を囲む輪（少し横長の、ゆがんだ楕円）。
  Path _ring(double center, double thickness) {
    final w = kNavChipSize * 1.3;
    final h = math.min(kNavChipSize + 10, thickness - 6);
    final cy = thickness / 2;
    // 手で描いた輪の様に、始点と終点が少しずれて重なる。
    final path = Path();
    const steps = 64;
    for (var i = 0; i <= steps + 4; i++) {
      final t = i / steps * 2 * math.pi + 0.5;
      final grow = 1 + 0.035 * math.sin(t * 2 + 1) + (i / steps) * 0.02;
      final x = center + math.cos(t) * w / 2 * grow;
      final y = cy + math.sin(t) * h / 2 * grow;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
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
    var path = _outline(length, thickness);
    var ring = center < 0 ? null : _ring(center, thickness);
    if (vertical) {
      // 横並びを、縦並びへ、時計回りに90度回す。
      final m =
          (Matrix4.identity()
                ..translateByDouble(size.width, 0, 0, 1)
                ..rotateZ(math.pi / 2))
              .storage;
      path = path.transform(m);
      ring = ring?.transform(m);
    }
    ChalkPaint.stroke(canvas, path, color, width: 2.4);
    if (ring != null) {
      ChalkPaint.stroke(canvas, ring, ringColor, width: 2.6, seed: 5);
    }
  }

  @override
  bool shouldRepaint(covariant _ChalkBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.vertical != vertical ||
      old.color != color ||
      old.ringColor != ringColor;
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
