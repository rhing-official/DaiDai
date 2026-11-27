import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/chalk/chalk_paint.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'kinari_nav_bar.dart' show paintKinariRecess;
import 'liquid_chip_highlight.dart';
import 'scribble_paint.dart';

/// 「描き」の時の、メニューチップの選択色（2026-11-26）。選ばれたチップを、アクセントカラーの
/// ペンが往復して塗りつぶす。外れたチップは、塗りが短く消える。塗りの上にだけ、選択中の文字色で
/// アイコンを描き直す（[LiquidChipHighlight]と同じ作り）。タッチは通さない。
class DrawChipHighlight extends ConsumerStatefulWidget {
  const DrawChipHighlight({
    required this.entries,
    required this.selectedIndex,
    required this.vertical,
    super.key,
  });

  final List<LiquidChipEntry> entries;
  final int? selectedIndex;
  final bool vertical;

  @override
  ConsumerState<DrawChipHighlight> createState() => _DrawChipHighlightState();
}

class _DrawChipHighlightState extends ConsumerState<DrawChipHighlight>
    with TickerProviderStateMixin {
  static const _drawDuration = Duration(milliseconds: 450);

  final Map<int, AnimationController> _controllers = {};
  final ValueNotifier<List<Rect?>> _rects = ValueNotifier(const []);
  int? _selected;

  AnimationController _controllerFor(int i, {double initial = 0}) =>
      _controllers.putIfAbsent(
        i,
        () => AnimationController(vsync: this, value: initial),
      );

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIndex;
    if (_selected != null) _controllerFor(_selected!, initial: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant DrawChipHighlight old) {
    super.didUpdateWidget(old);
    if (widget.selectedIndex != _selected) {
      final prev = _selected;
      _selected = widget.selectedIndex;
      // 外れた項目の塗りは、すぐに消す（クリックした項目以外には、アクセントカラーを描かない）。
      if (prev != null) {
        _controllerFor(prev)
          ..stop()
          ..value = 0;
      }
      final next = _selected;
      if (next != null) {
        final c = _controllerFor(next);
        c.value = 0;
        c.animateTo(1, duration: _drawDuration, curve: Curves.easeInOut);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _rects.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.attached) return;
    final rects = <Rect?>[
      for (final e in widget.entries)
        switch (e.chipKey.currentContext?.findRenderObject()) {
          final RenderBox box when box.attached && box.hasSize =>
            self.globalToLocal(box.localToGlobal(Offset.zero)) & box.size,
          _ => null,
        },
    ];
    final old = _rects.value;
    var changed = rects.length != old.length;
    for (var i = 0; !changed && i < rects.length; i++) {
      if (rects[i] != old[i]) changed = true;
    }
    if (changed) _rects.value = rects;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    if (!ref.watch(selectionDrawMotionProvider)) {
      return const SizedBox.shrink();
    }
    final style = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    final (Color fill, Color iconColor) = switch (style) {
      AppUiStyle.gekiga => (GekigaColors.onPanel, GekigaColors.panel),
      AppUiStyle.glass => (
        glassSelectedChipFill(context),
        scheme.onSurfaceVariant,
      ),
      _ => (scheme.primary, scheme.onPrimary),
    };
    return CustomPaint(
      painter: _DrawPainter(
        rects: _rects,
        controllers: _controllers,
        entries: widget.entries,
        fill: fill,
        iconColor: iconColor,
        square: style == AppUiStyle.gekiga,
        // 版画: 太い枠線（白い丸の縁）は残し、その内側だけを塗る。
        inset: style == AppUiStyle.block
            ? BlockTheme.borderWidth
            : style == AppUiStyle.kinari
            ? 3
            : 0,
        chalk: style == AppUiStyle.chalk,
        kinari: style == AppUiStyle.kinari,
        repaint: Listenable.merge([_rects, ..._controllers.values]),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  _DrawPainter({
    required this.rects,
    required this.controllers,
    required this.entries,
    required this.fill,
    required this.iconColor,
    required this.square,
    required this.inset,
    required this.chalk,
    this.kinari = false,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ValueNotifier<List<Rect?>> rects;
  final Map<int, AnimationController> controllers;
  final List<LiquidChipEntry> entries;
  final Color fill;
  final Color iconColor;
  final bool square;
  final double inset;
  final bool chalk;
  final bool kinari;

  Path _shape(Rect r) => square
      ? (Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(3))))
      : (Path()..addOval(r));

  @override
  void paint(Canvas canvas, Size size) {
    final list = rects.value;
    final bounds = (Offset.zero & size).inflate(80);
    canvas.saveLayer(bounds, Paint());
    var any = false;
    for (final entry in controllers.entries) {
      final i = entry.key;
      if (i >= list.length) continue;
      final r = list[i];
      final p = entry.value.value;
      if (r == null || p <= 0) continue;
      any = true;
      final inner = r.deflate(inset);
      ScribblePen.paint(canvas, inner, fill, p, clip: _shape(inner));
    }
    if (!any) {
      canvas.restore();
      return;
    }
    if (chalk) {
      Rect? area;
      for (final r in list) {
        if (r == null) continue;
        area = area == null ? r : area.expandToInclude(r);
      }
      if (area != null) ChalkPaint.punchGrain(canvas, area.inflate(40));
    }
    if (kinari) {
      paintKinariRecess(canvas, bounds, [
        for (final r in list)
          if (r != null) r.deflate(3),
      ]);
    }
    // 塗りの上にだけ、選択中の文字色でアイコンを描き直す。
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
    for (var i = 0; i < entries.length && i < list.length; i++) {
      final r = list[i];
      if (r == null) continue;
      final en = entries[i];
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(en.icon.codePoint),
          style: TextStyle(
            fontFamily: en.icon.fontFamily,
            package: en.icon.fontPackage,
            fontSize: en.iconSize,
            color: iconColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        r.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) =>
      old.fill != fill ||
      old.iconColor != iconColor ||
      old.square != square ||
      old.inset != inset ||
      old.chalk != chalk ||
      old.kinari != kinari ||
      old.entries != entries;
}
