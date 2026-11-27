import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/block/block_theme.dart' show findBlockFitBox;
import '../theme/gekiga/gekiga_colors.dart';
import 'liquid_paint.dart';
import 'liquid_sim.dart';
import 'ring_list_scope.dart';
import 'scribble_paint.dart';
import 'slide_chip_highlight.dart' show kSlideMotionCurve, kSlideMotionDuration;
import 'slide_select_list.dart' show SlidePositionScope;

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
    this.slidePosition,
    super.key,
  });

  /// 「滑り」の時、スワイプに追従させる位置（項目の並びの中の小数の番号。`null`の間は自前で滑る）。
  final ValueListenable<double?>? slidePosition;

  final int itemCount;
  final int? selectedIndex;
  final Widget child;
  final bool enabled;

  /// 囲みの時の、選択中の枠の角丸。一覧は、大ブロックの内側の余白に合わせて小さくする。
  final double ringRadius;

  /// 並びの水の計算（無ければ`null`）。劇画の箱の並びが、箱の塗りを水で描くのに使う。
  static LiquidSim? simOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidScope>()?.sim;

  /// 並びが「滑り」「描き」の時の、選ばれた見た目を現す範囲（無ければ`null`）。劇画の箱の並びが、
  /// 箱の塗りを、水と同じく、動きに合わせて描くのに使う（2026-11-27）。
  static TileReveal? revealOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidScope>()?.reveal;

  @override
  ConsumerState<LiquidTileGroup> createState() => _LiquidTileGroupState();
}

class _LiquidTileGroupState extends ConsumerState<LiquidTileGroup>
    with TickerProviderStateMixin {
  final LiquidSim _sim = LiquidSim();

  /// 滑り: 塗り1枚の位置（項目の座標）と、自前の移動のアニメーション。
  final _SlideSim _slide = _SlideSim();
  final TileDrawProgress _drawProgress = TileDrawProgress();
  late final TileReveal _slideReveal = _SlideReveal(_slide);
  late final TileReveal _drawReveal = DrawReveal(_drawProgress);
  late final AnimationController _slideController = AnimationController(
    vsync: this,
  )..addListener(_onSlideTick);
  double _slideFrom = 0;
  double _slideTo = 0;
  ValueListenable<double?>? _slidePosL;
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
    _slide.pos = _target?.toDouble();
    // 一覧をなぞる間の指の位置（`SlideSelectList`が渡す）。呼び出し側が位置を渡していればそちらを使う。
    _slidePosL = widget.slidePosition ?? SlidePositionScope.maybeOf(context);
    _slidePosL?.addListener(_onSlideExternal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _onSlideTick() => _slide.setPos(
    _slideFrom +
        (_slideTo - _slideFrom) *
            kSlideMotionCurve.transform(_slideController.value),
  );

  void _onSlideExternal() {
    final v = _slidePosL?.value;
    if (v == null) {
      // 指を離した。選ばれている項目へ収める。
      _slideToTarget();
      return;
    }
    _slideController.stop();
    _slide.setPos(v);
  }

  void _slideToTarget() {
    final target = _target?.toDouble();
    final current = _slide.pos;
    if (target == null || current == null || current == target) {
      _slideController.stop();
      _slide.setPos(target);
      return;
    }
    _slideFrom = current;
    _slideTo = target;
    _slideController.duration = kSlideMotionDuration;
    _slideController.forward(from: 0);
  }

  @override
  void dispose() {
    _slidePosL?.removeListener(_onSlideExternal);
    _slideController.dispose();
    _slide.dispose();
    _drawProgress.dispose();
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
    // 目に見える箱（文字の幅に縮めた箱）。行の幅と違う時、水はこちらの位置から流す。
    final blocks = <Rect?>[
      for (var i = 0; i < widget.itemCount; i++)
        switch (_keyFor(i).currentContext?.findRenderObject()) {
          final RenderBox box when box.attached && box.hasSize =>
            switch (findBlockFitBox(box)) {
              final RenderBox b when b.attached && b.hasSize =>
                self.globalToLocal(b.localToGlobal(Offset.zero)) & b.size,
              _ => null,
            },
          _ => null,
        },
    ];
    var changed = rects.length != _sim.rects.length;
    for (var i = 0; !changed && i < rects.length; i++) {
      if (rects[i] != _sim.rects[i]) changed = true;
    }
    for (var i = 0; !changed && i < blocks.length; i++) {
      if (i >= _sim.blocks.length || blocks[i] != _sim.blocks[i]) {
        changed = true;
      }
    }
    if (changed) {
      _sim.rects = rects;
      _sim.blocks = blocks;
      _sim.repaint();
    }
    if (ref.read(selectionSlideMotionProvider)) {
      _slide.setRects(rects);
      // 滑りへ切り替えた直後など、位置が選択とずれたままなら、選ばれている項目へ合わせる。
      if (!_slideController.isAnimating && _slidePosL?.value == null) {
        _slide.setPos(_target?.toDouble());
      }
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
    if (old.slidePosition != _slidePosL) {
      old.slidePosition?.removeListener(_onSlideExternal);
      _slidePosL?.addListener(_onSlideExternal);
    }
    if (widget.selectedIndex != _target) {
      final prev = _target;
      _target = widget.selectedIndex;
      _slideToTarget();
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
    final slide = widget.enabled && ref.watch(selectionSlideMotionProvider);
    final gekiga = style == AppUiStyle.gekiga;
    final fill = gekiga ? GekigaColors.onPanel : scheme.primary;
    // ガラスは、不透明で描いて層ごと透明にする（重なっても濃くならない）。
    final layerAlpha = style == AppUiStyle.glass ? 0.45 : 1.0;
    final draw = widget.enabled && ref.watch(selectionDrawMotionProvider);
    return _LiquidScope(
      draw: draw,
      drawProgress: draw ? _drawProgress : null,
      reveal: slide ? _slideReveal : (draw ? _drawReveal : null),
      slide: slide ? _slide : null,
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
    // 選択中の項目の背面を塗り潰す（2026-11-27）。塗りの上の文字・アイコンは、塗りの反対色にする。
    // 劇画も、他のデザインと同じく、大きな箱の中で、選択中の項目を白い箱で囲む。
    final body = _LiquidScope(
      sim: null,
      keyFor: _keyFor,
      selectedIndex: null,
      glass: false,
      ringSelectedIndex: ringNeedsOnPrimary(style) ? selected : null,
      ringOnColor: RingOnPrimary.colorFor(style),
      child: RingListBlock(withBackground: false, child: widget.child),
    );
    // 選択中の項目に重ねる層。選択が移ると、少し遅れて、次の項目へ滑る。
    Widget rectLayer(Widget Function() shape) => Positioned.fill(
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
                    child: shape(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: ringBlockBackground(context, style)),
        rectLayer(() => RingFill(style: style, radius: widget.ringRadius)),
        body,
        // 選択中の項目を囲む枠。選択が移ると、枠が次の項目へ、少し遅れて滑る。
        rectLayer(() => RingOutline(style: style, radius: widget.ringRadius)),
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
    this.drawProgress,
    this.reveal,
    this.slide,
    this.ringSelectedIndex,
    this.ringOnColor,
  });

  /// 塗りの上の文字色（無ければ`onPrimary`。劇画は黒）。
  final Color? ringOnColor;

  /// 囲み（生成り）で、背面がアクセントカラーで塗り潰される項目の番号。その項目の文字・アイコンは、
  /// 塗りの反対色にする。
  final int? ringSelectedIndex;

  /// 描きの項目が、塗りの進み具合を知らせる先（劇画の箱の塗りが読む）。
  final TileDrawProgress? drawProgress;

  /// 劇画の箱の塗りを、滑り・描きに合わせて描く窓口。
  final TileReveal? reveal;

  /// 滑り: 塗り1枚が滑る位置。
  final _SlideSim? slide;

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
      old.draw != draw ||
      old.reveal != reveal ||
      old.ringSelectedIndex != ringSelectedIndex ||
      old.slide != slide;
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
    final slide = scope.slide;
    if (slide != null) {
      return KeyedSubtree(
        key: scope.keyFor(widget.index),
        child: _SlideTile(
          sim: slide,
          index: widget.index,
          builder: widget.builder,
        ),
      );
    }
    if (scope.draw) {
      return KeyedSubtree(
        key: scope.keyFor(widget.index),
        child: _DrawTile(
          selected: scope.selectedIndex == widget.index,
          builder: widget.builder,
          index: widget.index,
          progress: scope.drawProgress,
        ),
      );
    }
    if (sim == null) {
      // 水を使わない時（丸で囲む等）。測るための鍵だけは付ける。
      final selected = scope.selectedIndex == widget.index;
      return KeyedSubtree(
        key: scope.keyFor(widget.index),
        // 囲みで塗り潰される項目は、ビルダーを、文字色を切り替える層（[RingOnPrimary]）の内側で呼ぶ。
        // 外で呼ぶと、ビルダーが、この`context`の`Theme`から文字色を決める部品（一対・広場の
        // トグルなど）に、塗りの反対色が届かず、白い塗りに白い文字になる（2026-11-27修正）。
        child: scope.ringSelectedIndex == widget.index
            ? RingOnPrimary(
                color: scope.ringOnColor,
                child: Builder(
                  builder: (inner) => widget.builder(inner, selected),
                ),
              )
            : widget.builder(context, selected),
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
  const _DrawTile({
    required this.selected,
    required this.builder,
    this.index,
    this.progress,
  });

  final bool selected;
  final Widget Function(BuildContext context, bool selected) builder;

  /// 塗りの進み具合を知らせる先と、並びの中の番号（劇画の箱の塗りが、同じ進み具合で描く為）。
  /// 無ければ、近くの[DrawIndexScope]を使う。
  final int? index;
  final TileDrawProgress? progress;

  @override
  State<_DrawTile> createState() => _DrawTileState();
}

class _DrawTileState extends State<_DrawTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
  )..addListener(_report);

  TileDrawProgress? _reportTo;
  int? _reportIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = DrawIndexScope.maybeOf(context);
    final to = widget.progress ?? scope?.progress;
    final index = widget.index ?? scope?.index;
    if (!identical(to, _reportTo) || index != _reportIndex) {
      _reportTo?.remove(_reportIndex);
      _reportTo = to;
      _reportIndex = index;
    }
  }

  void _report() => _reportTo?.set(_reportIndex, _c.value);

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
      // 外れた項目の塗りは、すぐに消す（クリックした項目以外には、アクセントカラーを描かない）。
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _reportTo?.remove(_reportIndex);
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

/// 描きの項目ごとの、塗りの進み具合（0〜1）。劇画の箱の塗りが、項目の文字と同じ進み具合で
/// 描く為に、項目が知らせる（2026-11-27）。知らせが無い項目は、選ばれているかどうかだけで決まる。
class TileDrawProgress extends ChangeNotifier {
  final Map<int, double> _values = {};

  double? valueOf(int index) => _values[index];

  void set(int? index, double value) {
    if (index == null || _values[index] == value) return;
    _values[index] = value;
    notifyListeners();
  }

  /// 項目が無くなった時。描き直しは、次の知らせで足りる為、知らせない。
  void remove(int? index) {
    if (index != null) _values.remove(index);
  }
}

/// 子（劇画の箱の1つ）が、描きの進み具合を知らせる先と、並びの中の番号。
class DrawIndexScope extends InheritedWidget {
  const DrawIndexScope({
    required this.progress,
    required this.index,
    required super.child,
    super.key,
  });

  final TileDrawProgress progress;
  final int index;

  static DrawIndexScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DrawIndexScope>();

  @override
  bool updateShouldNotify(DrawIndexScope old) =>
      !identical(progress, old.progress) || index != old.index;
}

/// 劇画の箱の塗りを、液体の水と同じように、動きに合わせて描く窓口（2026-11-27）。
/// 箱は、選ばれていない形を描いた上に、[paintRevealed]で、選ばれた形を現す範囲だけ重ねる。
abstract class TileReveal {
  /// 動きが進むたびに、箱を描き直す為の通知元。
  Listenable get listenable;

  /// [index]番目の箱（大きさ[size]）の、選ばれた形を、現す範囲だけ[paintSelected]で描く。
  /// [selected]は、その箱が選ばれているか（動きの情報が無い時の既定）。
  void paintRevealed(
    Canvas canvas,
    int index,
    Size size,
    bool selected,
    VoidCallback paintSelected,
  );
}

/// 滑り: 塗り1枚が重なる範囲だけ、選ばれた形を現す。
class _SlideReveal implements TileReveal {
  _SlideReveal(this._sim);

  final _SlideSim _sim;

  @override
  Listenable get listenable => _sim;

  @override
  void paintRevealed(
    Canvas canvas,
    int index,
    Size size,
    bool selected,
    VoidCallback paintSelected,
  ) {
    final rects = _sim.rects;
    final slab = _sim.slab;
    final tile = index < rects.length ? rects[index] : null;
    if (tile == null || slab == null) {
      if (selected) paintSelected();
      return;
    }
    final local = slab.shift(-tile.topLeft);
    // 塗りが項目をちょうど覆う時は、箱全体を選ばれた形にする（余白の端まで）。
    if ((slab.left - tile.left).abs() < 0.5 &&
        (slab.top - tile.top).abs() < 0.5 &&
        (slab.width - tile.width).abs() < 0.5 &&
        (slab.height - tile.height).abs() < 0.5) {
      paintSelected();
      return;
    }
    final region = local.intersect(Offset.zero & size);
    if (region.width <= 0.5 || region.height <= 0.5) return;
    canvas
      ..save()
      ..clipRect(region);
    paintSelected();
    canvas.restore();
  }
}

/// 描き: ペンで塗った所だけ、選ばれた形を現す（項目の文字と同じ進み具合）。
class DrawReveal implements TileReveal {
  DrawReveal(this._progress);

  final TileDrawProgress _progress;

  @override
  Listenable get listenable => _progress;

  @override
  void paintRevealed(
    Canvas canvas,
    int index,
    Size size,
    bool selected,
    VoidCallback paintSelected,
  ) {
    final p = _progress.valueOf(index) ?? (selected ? 1.0 : 0.0);
    if (p <= 0) return;
    if (p >= 1) {
      paintSelected();
      return;
    }
    final rect = Offset.zero & size;
    canvas.saveLayer(rect.inflate(2), Paint());
    paintSelected();
    // マスク: ペンで塗った所だけ残す（`ScribbleReveal`と同じ）。
    canvas.saveLayer(rect.inflate(2), Paint()..blendMode = BlendMode.dstIn);
    ScribblePen.paint(canvas, rect, Colors.black, p);
    canvas.restore();
    canvas.restore();
  }
}

/// 滑りの塗り1枚の位置（項目の並びの中の小数の番号）と、項目の矩形（並びの座標）。
class _SlideSim extends ChangeNotifier {
  List<Rect?> rects = const [];
  double? pos;

  void setPos(double? value) {
    if (value == pos) return;
    pos = value;
    notifyListeners();
  }

  void setRects(List<Rect?> value) {
    var changed = value.length != rects.length;
    for (var i = 0; !changed && i < value.length; i++) {
      if (value[i] != rects[i]) changed = true;
    }
    if (!changed) return;
    rects = value;
    notifyListeners();
  }

  /// 今の塗りの矩形。隣り合う2つの項目の矩形の間を補間する。
  Rect? get slab {
    final p = pos;
    if (p == null || rects.isEmpty) return null;
    final lo = p.floor().clamp(0, rects.length - 1);
    final hi = p.ceil().clamp(0, rects.length - 1);
    final a = rects[lo];
    final b = rects[hi];
    if (a == null || b == null) return a ?? b;
    return Rect.lerp(a, b, p - p.floor());
  }
}

/// 滑りの時の1項目。塗りの矩形が重なる範囲だけ、選ばれた見た目を出す。
class _SlideTile extends StatelessWidget {
  const _SlideTile({
    required this.sim,
    required this.index,
    required this.builder,
  });

  final _SlideSim sim;
  final int index;
  final Widget Function(BuildContext context, bool selected) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) {
        final tile = index < sim.rects.length ? sim.rects[index] : null;
        final slab = sim.slab;
        if (tile == null || slab == null) return builder(context, false);
        final overlap = slab.intersect(tile);
        if (overlap.width <= 0.5 || overlap.height <= 0.5) {
          return builder(context, false);
        }
        if ((slab.left - tile.left).abs() < 0.5 &&
            (slab.top - tile.top).abs() < 0.5 &&
            (slab.width - tile.width).abs() < 0.5 &&
            (slab.height - tile.height).abs() < 0.5) {
          return builder(context, true);
        }
        return Stack(
          children: [
            builder(context, false),
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  clipper: _FixedRectClipper(slab.shift(-tile.topLeft)),
                  child: builder(context, true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FixedRectClipper extends CustomClipper<Rect> {
  _FixedRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _FixedRectClipper old) => old.rect != rect;
}
