import 'package:flutter/foundation.dart' show ValueListenable;
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

/// 「滑り」の、クリックで切り替えた時の移動の長さと曲線（2026-11-27、ユーザー決定）。
const kSlideMotionDuration = Duration(milliseconds: 420);
const kSlideMotionCurve = Curves.easeInOutCubic;

/// 「滑り」の時の、メニューチップの選択色（2026-11-27）。チップは分けたまま、アクセントカラーの
/// 塗り1枚が、選択中のチップの下をゆっくり滑って移る。スワイプで切り替わる画面は
/// [externalPosition]に、並びの中の連続した位置（小数。2.5なら2番目と3番目の中間）を渡すと、
/// 塗りが指に追従する。`null`の間は、選択中のチップへ[kSlideMotionDuration]で滑る。
/// 塗りの上にだけ、選択中の文字色でアイコンを描き直す（[DrawChipHighlight]と同じ作り）。
/// タッチは通さない。
class SlideChipHighlight extends ConsumerStatefulWidget {
  const SlideChipHighlight({
    required this.entries,
    required this.selectedIndex,
    required this.vertical,
    this.externalPosition,
    super.key,
  });

  final List<LiquidChipEntry> entries;
  final int? selectedIndex;
  final bool vertical;

  /// 指・スワイプに追従させる位置。値が`null`の間は、自前のアニメーションで動く。
  final ValueListenable<double?>? externalPosition;

  @override
  ConsumerState<SlideChipHighlight> createState() => _SlideChipHighlightState();
}

class _SlideChipHighlightState extends ConsumerState<SlideChipHighlight>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<List<Rect?>> _rects = ValueNotifier(const []);

  /// 今の塗りの位置（並びの中の小数の番号）。
  final ValueNotifier<double?> _pos = ValueNotifier(null);
  late final AnimationController _controller = AnimationController(vsync: this);
  double _from = 0;
  double _to = 0;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIndex;
    if (_selected != null) _pos.value = _selected!.toDouble();
    _controller.addListener(_onTick);
    widget.externalPosition?.addListener(_onExternal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant SlideChipHighlight old) {
    super.didUpdateWidget(old);
    if (old.externalPosition != widget.externalPosition) {
      old.externalPosition?.removeListener(_onExternal);
      widget.externalPosition?.addListener(_onExternal);
    }
    if (widget.selectedIndex != _selected) {
      _selected = widget.selectedIndex;
      _slideToSelected();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    widget.externalPosition?.removeListener(_onExternal);
    _controller.dispose();
    _rects.dispose();
    _pos.dispose();
    super.dispose();
  }

  void _onTick() {
    _pos.value =
        _from + (_to - _from) * kSlideMotionCurve.transform(_controller.value);
  }

  /// 指に追従している間は、自前のアニメーションを止めて、渡された位置をそのまま使う。
  void _onExternal() {
    final v = widget.externalPosition?.value;
    if (v == null) {
      // 指を離した。選ばれているチップまで滑らせる（途中で止まらない）。
      _slideToSelected();
      return;
    }
    _controller.stop();
    _pos.value = v;
  }

  void _slideToSelected() {
    final target = _selected?.toDouble();
    if (target == null) {
      _controller.stop();
      _pos.value = null;
      return;
    }
    final current = _pos.value;
    if (current == null || current == target) {
      _controller.stop();
      _pos.value = target;
      return;
    }
    _from = current;
    _to = target;
    _controller.duration = kSlideMotionDuration;
    _controller.forward(from: 0);
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
    if (!ref.watch(selectionSlideMotionProvider)) {
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
      painter: _SlidePainter(
        rects: _rects,
        position: _pos,
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
      ),
    );
  }
}

class _SlidePainter extends CustomPainter {
  _SlidePainter({
    required this.rects,
    required this.position,
    required this.entries,
    required this.fill,
    required this.iconColor,
    required this.square,
    required this.inset,
    required this.chalk,
    this.kinari = false,
  }) : super(repaint: Listenable.merge([rects, position]));

  final ValueNotifier<List<Rect?>> rects;
  final ValueNotifier<double?> position;
  final List<LiquidChipEntry> entries;
  final Color fill;
  final Color iconColor;
  final bool square;
  final double inset;
  final bool chalk;
  final bool kinari;

  /// 位置（小数の番号）に対応する矩形。隣り合う2つのチップの矩形の間を補間する。
  Rect? _rectAt(List<Rect?> list, double p) {
    final lo = p.floor().clamp(0, list.length - 1);
    final hi = p.ceil().clamp(0, list.length - 1);
    final a = list[lo];
    final b = list[hi];
    if (a == null || b == null) return a ?? b;
    return Rect.lerp(a, b, p - p.floor());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final list = rects.value;
    final p = position.value;
    if (p == null || list.isEmpty) return;
    final r = _rectAt(list, p);
    if (r == null) return;
    final bounds = (Offset.zero & size).inflate(80);
    canvas.saveLayer(bounds, Paint());
    Path shapeOf(Rect rect) => square
        ? (Path()
            ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3))))
        : (Path()..addOval(rect));
    // 塗りは、メニューチップの中だけを動く（チップの間の領域には何も出さない）。
    final blob = shapeOf(r.deflate(inset));
    for (final cr in list) {
      if (cr == null) continue;
      final chip = cr.deflate(inset);
      if (!chip.overlaps(r)) continue;
      canvas.save();
      canvas.clipPath(shapeOf(chip));
      if (chalk) {
        ChalkPaint.fillPath(canvas, blob, fill);
      } else {
        canvas.drawPath(blob, Paint()..color = fill);
      }
      canvas.restore();
    }
    if (kinari) {
      paintKinariRecess(canvas, bounds, [
        for (final cr in list)
          if (cr != null) cr.deflate(3),
      ]);
    }
    // 塗りの上にだけ、選択中の文字色でアイコンを描き直す。
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
    for (var i = 0; i < entries.length && i < list.length; i++) {
      final cr = list[i];
      if (cr == null) continue;
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
        cr.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SlidePainter old) =>
      old.fill != fill ||
      old.iconColor != iconColor ||
      old.square != square ||
      old.inset != inset ||
      old.chalk != chalk ||
      old.kinari != kinari ||
      old.entries != entries;
}
