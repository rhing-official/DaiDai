import 'package:flutter/material.dart';

import '../theme/kinari/kinari_theme.dart';
import 'kinari_nav_bar.dart' show paintKinariInset, paintKinariInsetShadows;

/// 生成りスタイルの部品に共通の、へこみ・浮き（2026-11-27）。メニューチップの帯と同じ作りで、
/// 紙の面が、へこむ（内側の影と明かり）か、わずかに浮く（柔らかい影）。他のスタイルでは使わない。
class KinariSurface {
  KinariSurface._();

  /// わずかな浮きの影（柔らかく、薄い）。
  static List<BoxShadow> raisedShadows(Color ink) => [
    BoxShadow(
      color: ink.withValues(alpha: 0.22),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.5),
      blurRadius: 3,
      offset: const Offset(0, -1),
    ),
  ];

  /// 浮いた面の飾り。[color]は面の色、[line]があれば細い縁。
  static BoxDecoration raised({
    required Color color,
    required Color ink,
    double radius = 16,
    Color? line,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: line == null ? null : Border.all(color: line),
    boxShadow: raisedShadows(ink),
  );
}

/// へこんだ面。[child]の背面に、へこみを描く（内側の影と明かり）。
class KinariInset extends StatelessWidget {
  const KinariInset({
    required this.color,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.depth = 1,
    this.well,
    super.key,
  });

  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 指定すると、[color]の面（紙色）のへこみの中に、この色の面が、3px内側で、さらにへこんで嵌まる
  /// （選択中のアクセント色。面の周りに、へこみの縁が残る）。
  final Color? well;

  /// へこみの深さ（既定1。濃い色の面は、影が目立たない為、大きくする）。
  final double depth;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _InsetPainter(color, radius, depth, well),
    child: Padding(padding: padding, child: child),
  );
}

class _InsetPainter extends CustomPainter {
  _InsetPainter(this.base, this.radius, this.depth, this.well);

  final Color base;
  final double radius;
  final double depth;
  final Color? well;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final w = well;
    if (w == null) {
      paintKinariInset(canvas, outer, base, const Offset(1.5, 2), depth: depth);
      return;
    }
    paintKinariInset(canvas, outer, base, const Offset(1.5, 2));
    final inner = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(3),
      Radius.circular((radius - 3).clamp(0, 100).toDouble()),
    );
    paintKinariInset(
      canvas,
      inner,
      w,
      const Offset(1.5, 2),
      depth: depth,
      light: 0.3,
    );
  }

  @override
  bool shouldRepaint(covariant _InsetPainter old) =>
      old.base != base ||
      old.radius != radius ||
      old.depth != depth ||
      old.well != well;
}

/// 一覧の行の箱。選択中は、アクセントカラーの、へこんだ面。選ばれていない行は、へこんだ面。
/// 中の`ListTile`は、選択の塗りを持たせない（文字・アイコン色は[kinariTileForeground]）。
class KinariTileFrame extends StatelessWidget {
  const KinariTileFrame({
    required this.selected,
    required this.child,
    this.radius = 12,
    super.key,
  });

  final bool selected;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (selected) {
      // アクセントカラーの面も、へこませる（影を深くして、凹みが見えるようにする）。
      return KinariInset(
        color: scheme.surface,
        well: scheme.primary,
        radius: radius,
        depth: 2.2,
        child: child,
      );
    }
    return KinariInset(color: scheme.surface, radius: radius, child: child);
  }
}

/// 生成りの一覧の行の、選択中の文字・アイコン色。生成りでなければ`null`（既定のまま）。
Color? kinariTileForeground(BuildContext context, bool selected) =>
    selected && isKinariTheme(context)
    ? Theme.of(context).colorScheme.onPrimary
    : null;

/// 生成りのバナーの外枠。へこんだ面で、左右に余白を取る。
class KinariBannerFrame extends StatelessWidget {
  const KinariBannerFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: KinariInset(
      color: Theme.of(context).colorScheme.surface,
      radius: 12,
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

/// 生成りの、メッセージ画面の上のボタンの丸い札（メニューチップ）。へこんだ丸に、アイコン。
class KinariIconBadge extends StatelessWidget {
  const KinariIconBadge({required this.icon, this.size = 32, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KinariInset(
      color: scheme.surface,
      radius: size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.6, color: scheme.onSurface),
      ),
    );
  }
}

/// ポップアップ（ダイアログ・メニュー・シート）の形。細い縁に、内側の影と明かり（へこみ）を重ねる。
/// 面の色は、呼び出し側が少し濃い紙色で塗る。
class KinariInsetBorder extends RoundedRectangleBorder {
  const KinariInsetBorder({
    super.borderRadius,
    super.side,
    this.depth = 1,
    this.light = 1,
  });

  /// へこみの深さと、白い明かりの強さ。アクセントカラーの面（ボタン）は、深く、明かりは弱くする。
  final double depth;
  final double light;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final rrect = borderRadius.resolve(textDirection).toRRect(rect);
    paintKinariInsetShadows(
      canvas,
      rrect,
      const Offset(1.5, 2),
      depth: depth,
      light: light,
    );
    super.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  KinariInsetBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => KinariInsetBorder(
    borderRadius: borderRadius ?? this.borderRadius,
    side: side ?? this.side,
    depth: depth,
    light: light,
  );

  @override
  KinariInsetBorder scale(double t) => KinariInsetBorder(
    borderRadius: borderRadius * t,
    side: side.scale(t),
    depth: depth,
    light: light,
  );
}

/// へこんだ丸いボタン（生成り）。内側の影と明かりのある丸に、細い線を巡らせる。[color]は面の色（紙色、またはアクセント）、[lineColor]は線の色。
class KinariRaisedCircle extends StatelessWidget {
  const KinariRaisedCircle({
    required this.color,
    required this.lineColor,
    required this.size,
    required this.child,
    this.onTap,
    super.key,
  });

  final Color color;
  final Color lineColor;
  final double size;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _RaisedCirclePainter(color, lineColor),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _RaisedCirclePainter extends CustomPainter {
  _RaisedCirclePainter(this.color, this.line);

  final Color color;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    // へこんだ丸（内側の影と明かり）。浮かせない。
    paintKinariInset(
      canvas,
      RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      color,
      const Offset(2, 3),
      depth: 2,
    );
    canvas.drawCircle(
      rect.center,
      rect.shortestSide / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _RaisedCirclePainter old) =>
      old.color != color || old.line != line;
}
