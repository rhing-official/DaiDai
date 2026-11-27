import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/chalk/chalk_paint.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'draw_chip_highlight.dart';
import 'gekiga/monochrome_box.dart';
import 'liquid_paint.dart';
import 'liquid_sim.dart';
import 'slide_chip_highlight.dart';
import 'water_columns.dart';

/// 水が流れ込む塗りの1つ分。[chipKey]は、対象の[NavChip]に付けた鍵（位置と大きさを取る）。
class LiquidChipEntry {
  const LiquidChipEntry({
    required this.chipKey,
    required this.icon,
    required this.iconSize,
  });

  final GlobalKey chipKey;
  final IconData icon;
  final double iconSize;
}

/// メニューチップの選択色を、水槽の水が溢れて隣へ注ぐように移す層（2026-11-26）。
///
/// 各チップを水槽とみなす。選択が移ると、元のチップの水は、縁を越えて放物線を描いて落ち、
/// 次のチップへ注ぐ。糸は途中でちぎれて水滴になる。次のチップは、底から水位が上がり、
/// 水面は波打って収まる（高さ場、[WaterColumns]）。重力は常に画面の下。
/// 塗りの上にだけ、選択中の文字色でアイコンを描き直す。
///
/// タッチは通さない（[IgnorePointer]で包んで使う）。
class LiquidChipHighlight extends ConsumerStatefulWidget {
  const LiquidChipHighlight({
    required this.sim,
    required this.entries,
    required this.selectedIndex,
    required this.vertical,
    super.key,
  });

  /// 水の計算（[LiquidChipStrip]が持つ）。
  final LiquidSim sim;

  /// 並んでいる順のチップ。
  final List<LiquidChipEntry> entries;

  /// [entries]の中の、選択中の番号。無ければnull（水を出さない）。
  final int? selectedIndex;
  final bool vertical;

  /// 飛び出している（なぞっている間に強調される）チップの[entries]内の番号。

  @override
  ConsumerState<LiquidChipHighlight> createState() =>
      _LiquidChipHighlightState();
}

class _LiquidChipHighlightState extends ConsumerState<LiquidChipHighlight>
    with TickerProviderStateMixin {
  LiquidSim get _sim => widget.sim;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int? _target;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _target = widget.selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
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
    var changed = rects.length != _sim.rects.length;
    for (var i = 0; !changed && i < rects.length; i++) {
      if (rects[i] != _sim.rects[i]) changed = true;
    }
    if (changed) {
      _sim.rects = rects;
      _sim.repaint();
    }
    // 水の動きをオフからオンへ戻した時など、水槽が空のままなら、選ばれている項目を満水にする。
    if (_initialized &&
        _sim.tanks.isEmpty &&
        _target != null &&
        ref.read(navWaterMotionProvider)) {
      _sim.fillInstantly(_target!);
      _sim.repaint();
    }
    // 最初に測れた時、選択中のチップは、最初から満水にする（流れは出さない）。
    if (!_initialized && rects.any((r) => r != null)) {
      _initialized = true;
      final t = _target;
      if (t != null) {
        _sim.fillInstantly(t);
        _sim.repaint();
      }
    }
  }

  @override
  void didUpdateWidget(covariant LiquidChipHighlight old) {
    super.didUpdateWidget(old);
    if (widget.selectedIndex != _target) {
      final prev = _target;
      _target = widget.selectedIndex;
      if (ref.read(navWaterMotionProvider)) {
        _startTransition(prev, _target);
      } else {
        _settleInstantly();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// 水の動きがオフの間は、水槽を作り直して、選ばれている項目だけ満水にしておく
  /// （オンへ戻した時に、辻褄が合う）。
  void _settleInstantly() {
    _sim.streams.clear();
    _sim.drops.clear();
    _sim.tanks.clear();
    final t = _target;
    if (t != null) _sim.fillInstantly(t);
    _sim.repaint();
  }

  void _startTransition(int? prev, int? next) {
    _sim.startTransition(prev, next);
    _wake();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 20);
    final active = _sim.step(dt);
    _sim.repaint();
    if (!active) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    if (!ref.watch(navWaterMotionProvider)) {
      return const SizedBox.shrink();
    }
    final style = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    final (
      Color fill,
      Color iconColor,
      bool recolorIcons,
      double inset,
    ) = switch (style) {
      // 劇画: 枠の内側（枠の太さは箱の約18%）に収める。
      AppUiStyle.gekiga => (
        GekigaColors.onPanel,
        GekigaColors.panel,
        true,
        0.0,
      ),
      AppUiStyle.glass => (
        // 不透明な選択色（[glassSelectedChipFill]）。重なっても、色が変わらない。
        glassSelectedChipFill(context),
        scheme.onSurfaceVariant,
        false,
        // 縁は、チップと同じ円にそろえる（内側へ収めると、縁が暗くなる）。
        0.0,
      ),
      AppUiStyle.block => (
        scheme.primary,
        scheme.onPrimary,
        true,
        BlockTheme.borderWidth,
      ),
      _ => (scheme.primary, scheme.onPrimary, true, 0.0),
    };
    return CustomPaint(
      painter: _WaterPainter(
        sim: _sim,
        entries: widget.entries,
        vertical: widget.vertical,
        fill: fill,
        iconColor: iconColor,
        recolorIcons: recolorIcons,
        inset: inset,
        square: style == AppUiStyle.gekiga,
        layerAlpha: 1.0,
        glassInChip: style == AppUiStyle.glass,
        chalk: style == AppUiStyle.chalk,
      ),
    );
  }
}

class _WaterPainter extends CustomPainter {
  _WaterPainter({
    required this.sim,
    required this.entries,
    required this.vertical,
    required this.fill,
    required this.iconColor,
    required this.recolorIcons,
    required this.inset,
    required this.square,
    required this.layerAlpha,
    required this.glassInChip,
    this.chalk = false,
  }) : super(repaint: sim);

  final LiquidSim sim;
  final List<LiquidChipEntry> entries;
  final bool vertical;
  final Color fill;
  final Color iconColor;
  final bool recolorIcons;
  final double inset;
  final bool square;

  /// 層全体の透明度。水の塗りを重ねて描いても、色が濃くならない為、層ごとにかける。
  final double layerAlpha;

  /// ガラスは、水を[NavChip]の中で描く。
  final bool glassInChip;

  /// チョーク: 水の塗りを、チョークで塗った質感にする（粉の抜け・斜めのかすれ）。
  final bool chalk;

  Path _shapeOf(Offset center, double half) => square
      ? (Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: half * 2, height: half * 2),
            const Radius.circular(3),
          ),
        ))
      : (Path()..addOval(Rect.fromCircle(center: center, radius: half)));

  @override
  void paint(Canvas canvas, Size size) {
    final rects = sim.rects;
    final bounds = (Offset.zero & size).inflate(80);
    final paint = Paint()..color = fill;
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(0, 0, 0, layerAlpha),
    );

    // 水槽: 水位まで水を入れ、水面を揺らす。
    for (final entry in sim.tanks.entries) {
      final i = entry.key;
      if (i >= rects.length) continue;
      final r = rects[i];
      if (r == null) continue;
      final tank = entry.value;
      // ガラスは、水をチップの中（[NavChip]）で描く。重ね方を、選択色の塗りと同じにする為。
      if (tank.isEmpty || glassInChip) continue;
      final center = r.center;
      final half = r.shortestSide / 2 - inset;
      final box = Rect.fromCenter(
        center: center,
        width: half * 2,
        height: half * 2,
      );
      if (square && i < entries.length) {
        // 劇画: 選ばれた箱（白い外枠・黒い中枠・白い塗り）そのものを、水の形で現す。
        // 水が収まった時の見た目が、水の動きをオフにした時と同じになる。
        canvas.save();
        canvas.translate(box.left, box.top);
        if (!tank.isFull) canvas.clipPath(sim.waterRegion(i, box.size));
        MonochromeBoxPainter(
          vertices: [
            Offset.zero,
            Offset(box.width, 0),
            Offset(box.width, box.height),
            Offset(0, box.height),
          ],
          thicknessBase: box.width,
          fillColor: fill,
          seed: entries[i].icon.hashCode,
          invert: true,
        ).paint(canvas, box.size);
        canvas.restore();
        continue;
      }
      final shape = _shapeOf(center, half);
      if (tank.isFull) {
        canvas.drawPath(shape, paint);
        continue;
      }
      canvas.save();
      canvas.clipPath(shape);
      canvas.translate(box.left, box.top);
      canvas.drawPath(sim.waterRegion(i, box.size), paint);
      canvas.restore();
    }

    paintLiquidStreamAndDrops(canvas, sim, fill, square: square);

    if (chalk) {
      Rect? area;
      for (final r in rects) {
        if (r == null) continue;
        area = area == null ? r : area.expandToInclude(r);
      }
      if (area != null) ChalkPaint.punchGrain(canvas, area.inflate(40));
    }

    if (recolorIcons) {
      // 水の上にだけ、選択中の文字色でアイコンを描き直す。
      canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
      for (var i = 0; i < entries.length && i < rects.length; i++) {
        final r = rects[i];
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
        final c = r.center;
        painter.paint(
          canvas,
          c - Offset(painter.width / 2, painter.height / 2),
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterPainter old) =>
      old.fill != fill ||
      old.iconColor != iconColor ||
      old.square != square ||
      old.layerAlpha != layerAlpha ||
      old.glassInChip != glassInChip ||
      old.chalk != chalk ||
      old.inset != inset ||
      old.entries != entries;
}

/// 水が流れ込むメニューチップの、帯。[child]（`liquid: true`の[NavChip]を並べたもの）の上に
/// [LiquidChipHighlight]を重ねる。
class LiquidChipStrip extends StatefulWidget {
  const LiquidChipStrip({
    required this.child,
    required this.entries,
    required this.selectedIndex,
    required this.vertical,
    this.slidePosition,
    super.key,
  });

  final Widget child;
  final List<LiquidChipEntry> entries;
  final int? selectedIndex;
  final bool vertical;

  /// 滑りの時、スワイプに追従させる位置（並びの中の小数の番号。`null`の間は自前で動く）。
  final ValueListenable<double?>? slidePosition;

  @override
  State<LiquidChipStrip> createState() => _LiquidChipStripState();
}

class _LiquidChipStripState extends State<LiquidChipStrip> {
  final LiquidSim _sim = LiquidSim();

  @override
  void dispose() {
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidChipScope(
      sim: _sim,
      chipKeys: [for (final e in widget.entries) e.chipKey],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: LiquidChipHighlight(
                sim: _sim,
                entries: widget.entries,
                selectedIndex: widget.selectedIndex,
                vertical: widget.vertical,
              ),
            ),
          ),
          // 描き: ペンで塗る層（描きの時だけ描く）。
          Positioned.fill(
            child: IgnorePointer(
              child: DrawChipHighlight(
                entries: widget.entries,
                selectedIndex: widget.selectedIndex,
                vertical: widget.vertical,
              ),
            ),
          ),
          // 滑り: 塗り1枚が滑る層（滑りの時だけ描く）。
          Positioned.fill(
            child: IgnorePointer(
              child: SlideChipHighlight(
                entries: widget.entries,
                selectedIndex: widget.selectedIndex,
                vertical: widget.vertical,
                externalPosition: widget.slidePosition,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [LiquidChipStrip]の水の計算を、中のチップへ渡す。ガラスのチップは、水を自分の中で描く。
class LiquidChipScope extends InheritedWidget {
  const LiquidChipScope({
    required this.sim,
    required this.chipKeys,
    required super.child,
    super.key,
  });

  final LiquidSim sim;
  final List<GlobalKey> chipKeys;

  /// [key]のチップの水の計算と番号（無ければ`null`）。
  static (LiquidSim, int)? of(BuildContext context, Key? key) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiquidChipScope>();
    if (scope == null || key == null) return null;
    final index = scope.chipKeys.indexOf(key as GlobalKey);
    return index < 0 ? null : (scope.sim, index);
  }

  @override
  bool updateShouldNotify(LiquidChipScope old) =>
      sim != old.sim || old.chipKeys.length != chipKeys.length;
}

/// ガラスの選択中のチップの色。背景にアクセント色を45%で重ねた、不透明な色。
Color glassSelectedChipFill(BuildContext context) => Color.alphaBlend(
  Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
  Theme.of(context).scaffoldBackgroundColor,
);

/// ガラスのチップの中で、水を描く。選択色の塗り（半透明）と同じ場所・同じ重ね方になる。
class LiquidGlassFillPainter extends CustomPainter {
  LiquidGlassFillPainter(this.sim, this.index, this.color)
    : super(repaint: sim);

  final LiquidSim sim;
  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final tank = sim.tanks[index];
    if (tank == null || tank.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.clipPath(Path()..addOval(bounds));
    final paint = Paint()..color = color;
    if (tank.isFull) {
      canvas.drawRect(bounds, paint);
    } else {
      canvas.drawPath(sim.waterRegion(index, size), paint);
    }
  }

  @override
  bool shouldRepaint(covariant LiquidGlassFillPainter old) =>
      old.sim != sim || old.index != index || old.color != color;
}
