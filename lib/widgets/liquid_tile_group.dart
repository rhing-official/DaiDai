import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'liquid_paint.dart';
import 'liquid_sim.dart';
import 'ring_list_scope.dart';
import 'scribble_paint.dart';

/// 項目の並び（設定・身だしなみのカテゴリ一覧、語らいの一対・広場のタブ）の、選択色を、
/// 水が流れ込むように移す（2026-11-26）。チップは[LiquidChipHighlight]、こちらは文字のある
/// 項目用。
///
/// 項目の見た目は、選ばれていない版と選ばれた版を重ねて描き、選ばれた版を水の領域
/// （水位・波）で切り抜く。文字や枠も、水の上だけが選択色になる。項目の間を流れる糸と
/// 水滴は、並びの上に重ねて描く。
///
/// 項目は、`LiquidTile`で包む。劇画のように、並び全体をまとめて描く作りは[enabled]を
/// `false`にして使わない（従来どおり、即時に切り替わる）。
class LiquidTileGroup extends ConsumerStatefulWidget {
  const LiquidTileGroup({
    required this.itemCount,
    required this.selectedIndex,
    required this.child,
    this.enabled = true,
    this.ringRadius = 12,
    super.key,
  });

  final int itemCount;
  final int? selectedIndex;
  final Widget child;
  final bool enabled;

  /// 囲みの時の、選択中の枠の角丸。一覧は、大ブロックの内側の余白に合わせて小さくする。
  final double ringRadius;

  /// 並びの水の計算（無ければ`null`）。劇画の箱の並びが、箱の塗りを水で描くのに使う。
  static LiquidSim? simOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidScope>()?.sim;

  @override
  ConsumerState<LiquidTileGroup> createState() => _LiquidTileGroupState();
}

class _LiquidTileGroupState extends ConsumerState<LiquidTileGroup>
    with SingleTickerProviderStateMixin {
  final LiquidSim _sim = LiquidSim();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int? _target;
  bool _initialized = false;
  final List<GlobalKey> _keys = [];

  GlobalKey _keyFor(int i) {
    while (_keys.length <= i) {
      _keys.add(GlobalKey());
    }
    return _keys[i];
  }

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
    _sim.dispose();
    super.dispose();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _measure() {
    if (!mounted || !widget.enabled) return;
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.attached) return;
    final rects = <Rect?>[
      for (var i = 0; i < widget.itemCount; i++)
        switch (_keyFor(i).currentContext?.findRenderObject()) {
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
        ref.read(selectionWaterMotionProvider)) {
      _sim.fillInstantly(_target!);
      _sim.repaint();
    }
    // 最初に測れた時、選ばれている項目は、最初から満水にする（流れは出さない）。
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
  void didUpdateWidget(covariant LiquidTileGroup old) {
    super.didUpdateWidget(old);
    if (widget.selectedIndex != _target) {
      final prev = _target;
      _target = widget.selectedIndex;
      if (widget.enabled && ref.read(selectionWaterMotionProvider)) {
        _sim.startTransition(prev, _target);
        _wake();
      } else {
        _sim.streams.clear();
        _sim.drops.clear();
        _sim.tanks.clear();
        final t = _target;
        if (t != null) _sim.fillInstantly(t);
        _sim.repaint();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
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
    final style = ref.watch(appUiStyleProvider);
    // 「丸で囲む」: 項目を1つの大きなブロックにまとめ、選択中を線の枠で囲む（水は使わない）。
    if (widget.enabled && ref.watch(navBandMergedProvider)) {
      return _buildRing(context, style);
    }
    final scheme = Theme.of(context).colorScheme;
    final water = ref.watch(selectionWaterMotionProvider);
    final gekiga = style == AppUiStyle.gekiga;
    final fill = gekiga ? GekigaColors.onPanel : scheme.primary;
    // ガラスは、不透明で描いて層ごと透明にする（重なっても濃くならない）。
    final layerAlpha = style == AppUiStyle.glass ? 0.45 : 1.0;
    return _LiquidScope(
      draw: widget.enabled && ref.watch(selectionDrawMotionProvider),
      sim: widget.enabled && water ? _sim : null,
      keyFor: _keyFor,
      selectedIndex: widget.selectedIndex,
      glass: style == AppUiStyle.glass,
      child: widget.enabled && water
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _StreamPainter(_sim, fill, gekiga, layerAlpha),
                    ),
                  ),
                ),
              ],
            )
          : widget.child,
    );
  }
}

extension on _LiquidTileGroupState {
  Widget _buildRing(BuildContext context, AppUiStyle style) {
    final selected = widget.selectedIndex;
    // 項目は、選択の見た目（塗り）を出さない（選択は、枠で表す）。
    final body = _LiquidScope(
      sim: null,
      keyFor: _keyFor,
      selectedIndex: null,
      glass: false,
      child: RingListBlock(withBackground: false, child: widget.child),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (style != AppUiStyle.gekiga)
          Positioned.fill(child: ringBlockBackground(context, style)),
        body,
        // 選択中の項目を囲む枠。選択が移ると、枠が次の項目へ、少し遅れて滑る。
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _sim,
              builder: (context, _) {
                final rects = _sim.rects;
                final rect = selected != null && selected < rects.length
                    ? rects[selected]
                    : null;
                if (rect == null) return const SizedBox.shrink();
                return TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: rect),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, r, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fromRect(
                        rect: (r ?? rect).deflate(1),
                        child: RingOutline(
                          style: style,
                          radius: widget.ringRadius,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StreamPainter extends CustomPainter {
  _StreamPainter(this.sim, this.fill, this.square, this.layerAlpha)
    : super(repaint: sim);

  final LiquidSim sim;
  final Color fill;
  final bool square;
  final double layerAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      (Offset.zero & size).inflate(80),
      Paint()..color = Color.fromRGBO(0, 0, 0, layerAlpha),
    );
    paintLiquidStreamAndDrops(canvas, sim, fill, square: square);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StreamPainter old) =>
      old.fill != fill || old.square != square || old.layerAlpha != layerAlpha;
}

class _LiquidScope extends InheritedWidget {
  const _LiquidScope({
    required this.sim,
    required this.keyFor,
    required this.selectedIndex,
    required this.glass,
    required super.child,
    this.draw = false,
  });

  /// 描き: 選ばれた見た目を、ペンで往復して塗るように現す。
  final bool draw;

  /// ガラスか。半透明の塗りが文字に重ならないよう、水の外だけに、選ばれていない版を出す。
  final bool glass;
  final LiquidSim? sim;
  final GlobalKey Function(int) keyFor;
  final int? selectedIndex;

  @override
  bool updateShouldNotify(_LiquidScope old) =>
      old.sim != sim ||
      old.selectedIndex != selectedIndex ||
      old.glass != glass ||
      old.draw != draw;
}

/// [LiquidTileGroup]の中の1項目。[builder]は、選ばれた見た目（`true`）と選ばれていない見た目
/// （`false`）を返す。水の中だけが、選ばれた見た目になる。
///
/// 水位が空か満水の間は、片方の見た目だけを出す（重ねるのは、水が動いている間だけ）。
class LiquidTile extends StatefulWidget {
  const LiquidTile({required this.index, required this.builder, super.key});

  final int index;
  final Widget Function(BuildContext context, bool selected) builder;

  @override
  State<LiquidTile> createState() => _LiquidTileState();
}

enum _TileMode { empty, full, mixed }

class _LiquidTileState extends State<LiquidTile> {
  LiquidSim? _sim;
  _TileMode? _mode;

  _TileMode _modeOf(LiquidSim sim, bool selectedInitially) {
    final t = sim.tanks[widget.index];
    if (t == null) {
      return selectedInitially ? _TileMode.full : _TileMode.empty;
    }
    if (t.isEmpty && sim.selected != widget.index) return _TileMode.empty;
    if (t.isFull && sim.selected == widget.index) return _TileMode.full;
    return _TileMode.mixed;
  }

  void _onSim() {
    final sim = _sim;
    if (sim == null || !mounted) return;
    final scope = context.getInheritedWidgetOfExactType<_LiquidScope>();
    final mode = _modeOf(sim, scope?.selectedIndex == widget.index);
    if (mode != _mode) setState(() => _mode = mode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<_LiquidScope>();
    final sim = scope?.sim;
    if (!identical(sim, _sim)) {
      _sim?.removeListener(_onSim);
      _sim = sim;
      sim?.addListener(_onSim);
    }
    if (sim != null) {
      _mode = _modeOf(sim, scope?.selectedIndex == widget.index);
    }
  }

  @override
  void dispose() {
    _sim?.removeListener(_onSim);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_LiquidScope>();
    final sim = scope?.sim;
    if (scope == null) return widget.builder(context, false);
    if (scope.draw) {
      return KeyedSubtree(
        key: scope.keyFor(widget.index),
        child: _DrawTile(
          selected: scope.selectedIndex == widget.index,
          builder: widget.builder,
        ),
      );
    }
    if (sim == null) {
      // 水を使わない時（丸で囲む等）。測るための鍵だけは付ける。
      return KeyedSubtree(
        key: scope.keyFor(widget.index),
        child: widget.builder(context, scope.selectedIndex == widget.index),
      );
    }
    final mode = _mode ?? _modeOf(sim, scope.selectedIndex == widget.index);
    final Widget body = switch (mode) {
      _TileMode.empty => widget.builder(context, false),
      _TileMode.full => widget.builder(context, true),
      _TileMode.mixed => Stack(
        children: [
          scope.glass
              ? _OutsideWaterClip(
                  sim: sim,
                  index: widget.index,
                  child: widget.builder(context, false),
                )
              : widget.builder(context, false),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipPath(
                clipper: _WaterClipper(sim, widget.index),
                child: widget.builder(context, true),
              ),
            ),
          ),
        ],
      ),
    };
    return KeyedSubtree(key: scope.keyFor(widget.index), child: body);
  }
}

class _WaterClipper extends CustomClipper<Path> {
  _WaterClipper(this.sim, this.index) : super(reclip: sim);

  final LiquidSim sim;
  final int index;

  @override
  Path getClip(Size size) => sim.waterRegion(index, size);

  @override
  bool shouldReclip(covariant _WaterClipper old) =>
      old.sim != sim || old.index != index;
}

/// 水の外側だけを描く（タッチは、全体で受ける）。ガラスの選択色は半透明なので、水の下に
/// 選ばれていない版の文字が残ると、色が重なって濁る。
class _OutsideWaterClip extends SingleChildRenderObjectWidget {
  const _OutsideWaterClip({
    required this.sim,
    required this.index,
    required super.child,
  });

  final LiquidSim sim;
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOutsideWaterClip(sim, index);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderOutsideWaterClip renderObject,
  ) {
    renderObject
      ..sim = sim
      ..index = index;
  }
}

class _RenderOutsideWaterClip extends RenderProxyBox {
  _RenderOutsideWaterClip(this._sim, this._index);

  LiquidSim _sim;
  int _index;

  set sim(LiquidSim value) {
    if (identical(_sim, value)) return;
    if (attached) _sim.removeListener(markNeedsPaint);
    _sim = value;
    if (attached) _sim.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set index(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sim.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _sim.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = Offset.zero & size;
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(bounds),
      _sim.waterRegion(_index, size),
    );
    context.pushClipPath(
      needsCompositing,
      offset,
      bounds,
      outside,
      super.paint,
    );
  }
}

/// 一覧の行用。選択の動きが「描き」の時だけ、選ばれた見た目を、ペンで塗るように現す。
/// それ以外は、そのまま[builder]を呼ぶ。
class DrawSelectionTile extends ConsumerWidget {
  const DrawSelectionTile({
    required this.selected,
    required this.builder,
    super.key,
  });

  final bool selected;
  final Widget Function(BuildContext context, bool selected) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(selectionMotionProvider) != SelectionMotion.draw) {
      return builder(context, selected);
    }
    return _DrawTile(selected: selected, builder: builder);
  }
}

/// 描き: 選ばれた見た目を、ペンが往復して塗るように現す（選択が外れた時は、塗りが短く消える）。
class _DrawTile extends StatefulWidget {
  const _DrawTile({required this.selected, required this.builder});

  final bool selected;
  final Widget Function(BuildContext context, bool selected) builder;

  @override
  State<_DrawTile> createState() => _DrawTileState();
}

class _DrawTileState extends State<_DrawTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _DrawTile old) {
    super.didUpdateWidget(old);
    if (widget.selected == old.selected) return;
    if (widget.selected) {
      _c.value = 0;
      _c.animateTo(
        1,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } else {
      _c.animateBack(
        0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeIn,
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final p = _c.value;
        if (p <= 0) return widget.builder(context, false);
        if (p >= 1) return widget.builder(context, true);
        return Stack(
          children: [
            widget.builder(context, false),
            Positioned.fill(
              child: IgnorePointer(
                child: ScribbleReveal(
                  progress: p,
                  child: widget.builder(context, true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
