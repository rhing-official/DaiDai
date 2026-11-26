import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/chalk/chalk_paint.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'glass/glass_surface.dart';
import 'washi_nav_bar.dart';

/// 「丸で囲む」の時の項目の並び（2026-11-26）。項目の箱を1つの大きなブロックにまとめ、選択中の
/// 項目を線の枠（角丸）で囲む。この範囲の中の項目は、自分の箱・塗りを描かない（枠と塗りは、
/// 並びが描く）。中のウィジェットからは、[RingListScope.styleOf]で、外側のUIスタイルが分かる。
class RingListScope extends InheritedWidget {
  const RingListScope({required this.style, required super.child, super.key});

  /// 外側の（本当の）UIスタイル。中は、項目が自前の箱を描かないよう、フラット扱いにしてある。
  final AppUiStyle style;

  /// この範囲の中なら、外側のUIスタイル。範囲の外ならnull。
  static AppUiStyle? styleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RingListScope>()?.style;

  @override
  bool updateShouldNotify(RingListScope old) => old.style != style;
}

class _FlatStyleNotifier extends AppUiStyleNotifier {
  @override
  AppUiStyle build() => AppUiStyle.flat;
}

/// 「丸で囲む」の時だけ、[child]（項目の並び）を、1つの大きなブロックの中に置き、中の項目から、
/// 箱・選択の塗りを取り除く。それ以外の時、劇画（並び全体を既に1つの箱で描く）は、[child]をそのまま返す。
///
/// 項目は、UIスタイルをフラットとして描くようにしてある（枠付きの箱・ガラス・選択の塗りは
/// 出ない）。選択中の枠は、並びの種類ごとに、[RingOutline]で重ねる。
class RingListBlock extends ConsumerWidget {
  const RingListBlock({
    required this.child,
    this.withBackground = true,
    this.fitContent = false,
    super.key,
  });

  final Widget child;

  /// 大きなブロックの背景を、ここで描くか。`false`なら、呼び出し側が描く（枠だけ重ねる）。
  final bool withBackground;

  /// 大きなブロックを、中身（項目）の高さまでで区切るか（2026-11-26）。`false`なら、置かれた領域の
  /// 下まで広げる。`true`の時は、[child]を、中身の高さに縮める形（`ListView`なら`shrinkWrap: true`）に
  /// すること。中身が領域より高い時は、領域の高さで止まり、中でスクロールする。
  final bool fitContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    if (!ref.watch(navBandMergedProvider) || style == AppUiStyle.gekiga) {
      return child;
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 項目の塗り（面の色）は透明にする。枠付きの箱の判定（拡張）も外す。
    final plain = theme.copyWith(
      // 項目にホバーしても、半透明の色を重ねない（2026-11-26）。
      hoverColor: Colors.transparent,
      colorScheme: scheme.copyWith(
        surface: Colors.transparent,
        // 版画・チョークの項目は、文字を、設定のフォントカラー（onSurface）で描く。フラット扱いに
        // すると、控えめな色（onSurfaceVariant）になり、設定と違って見えるので、そろえる。
        onSurfaceVariant: style == AppUiStyle.block || style == AppUiStyle.chalk
            ? scheme.onSurface
            : null,
      ),
      extensions: [
        for (final e in theme.extensions.values)
          if (e is! BlockThemeMarker &&
              !e.runtimeType.toString().contains('Chalk'))
            e,
      ],
    );
    final body = ProviderScope(
      overrides: [appUiStyleProvider.overrideWith(_FlatStyleNotifier.new)],
      child: Theme(
        data: plain,
        child: RingListScope(
          style: style,
          child: withBackground
              ? RingSlideHost(
                  style: style,
                  child: RingHitExtender(child: child),
                )
              : RingHitExtender(child: child),
        ),
      ),
    );
    if (!withBackground) return body;
    final block = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: ringBlockBackground(context, style)),
        body,
      ],
    );
    if (!fitContent) return block;
    // 背景は、中身の高さまで。領域より高ければ、領域の高さで止まる。
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [Flexible(child: block)],
    );
  }
}

/// 大きなブロックの背景（スタイルごと）。劇画は、並びが自分で描くので、ここでは描かない。
Widget ringBlockBackground(BuildContext context, AppUiStyle style) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final brightness = theme.brightness;
  switch (style) {
    case AppUiStyle.glass:
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox.expand(),
      );
    case AppUiStyle.block:
      return DecoratedBox(
        decoration: BoxDecoration(
          color: brightness == Brightness.light ? Colors.white : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: BlockTheme.lineColor(brightness),
            width: BlockTheme.borderWidth,
          ),
          boxShadow: BlockTheme.shadow(scheme.primary, brightness),
        ),
      );
    case AppUiStyle.chalk:
      // メニューチップの帯と同じ: 塗らず、チョークの線の枠だけ。
      return DecoratedBox(
        decoration: ChalkBoxDecoration(
          borderRadius: BorderRadius.circular(16),
          lineColor: scheme.onSurface,
          lineWidth: 2.4,
        ),
      );
    case AppUiStyle.washi:
      // メニューチップの帯と同じ: へこんだ面。
      return CustomPaint(painter: WashiInsetBlockPainter(scheme.surface, 16));
    case AppUiStyle.gekiga:
      return const SizedBox.shrink();
    case AppUiStyle.flat:
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
      );
  }
}

/// 選択中の項目を囲む、線の角丸の枠（塗らない）。アクセントカラーの線（劇画は白）。メニューチップの丸と同じ。
class RingOutline extends StatelessWidget {
  const RingOutline({required this.style, this.radius = 12, super.key});

  final AppUiStyle style;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = BorderRadius.circular(style == AppUiStyle.gekiga ? 3 : radius);
    if (style == AppUiStyle.chalk) {
      return DecoratedBox(
        decoration: ChalkBoxDecoration(
          borderRadius: r,
          lineColor: scheme.primary,
          lineWidth: 2.2,
        ),
      );
    }
    final (Color color, double width) = switch (style) {
      AppUiStyle.glass => (scheme.onSurface.withValues(alpha: 0.7), 1.6),
      AppUiStyle.block => (
        BlockTheme.lineColor(theme.brightness),
        BlockTheme.borderWidth,
      ),
      AppUiStyle.gekiga => (GekigaColors.onPanel, 3),
      AppUiStyle.washi => (scheme.primary, 1.8),
      _ => (scheme.primary, 2),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: color, width: width),
      ),
    );
  }
}

/// 囲みの大きなブロックの中で、項目の押せる範囲を、ブロックの端いっぱいまで広げる（2026-11-26）。
/// 見た目（余白・枠）は変えない。ブロックの左右の余白（[edgeInset]）と、上端・下端の余白
/// （[edgeInsetY]）を押した時は、内側の一番近い位置の項目を押したことにし、項目と項目の隙間の横
/// （[gapProbe]まで）を押した時は、近い項目を押したことにする。押した位置から、項目の中の位置は、
/// 余白の分だけずれて届く（タップの判定には影響しない）。
class RingHitExtender extends SingleChildRenderObjectWidget {
  const RingHitExtender({
    required Widget super.child,
    this.edgeInset = 8,
    this.edgeInsetY = 12,
    this.gapProbe = 3,
    super.key,
  });

  final double edgeInset;
  final double edgeInsetY;
  final double gapProbe;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRingHitExtender(edgeInset, edgeInsetY, gapProbe);

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    (renderObject as _RenderRingHitExtender)
      ..edgeInset = edgeInset
      ..edgeInsetY = edgeInsetY
      ..gapProbe = gapProbe;
  }
}

class _RenderRingHitExtender extends RenderProxyBox {
  _RenderRingHitExtender(this.edgeInset, this.edgeInsetY, this.gapProbe);

  double edgeInset;
  double edgeInsetY;
  double gapProbe;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final maxX = size.width - 1e-3;
    final maxY = size.height - 1e-3;
    final insetX = edgeInset.clamp(0.0, size.width / 2).toDouble();
    final insetY = edgeInsetY.clamp(0.0, size.height / 2).toDouble();
    // 端の余白は、スクロールの部品が全面で受けるため、先に、内側へ寄せた位置で、項目を探す。
    final cx = position.dx.clamp(insetX, maxX - insetX).toDouble();
    final cy = position.dy.clamp(insetY, maxY - insetY).toDouble();
    if (cx != position.dx || cy != position.dy) {
      if (super.hitTest(result, position: Offset(cx, cy))) return true;
    }
    if (super.hitTest(result, position: position)) return true;
    for (var d = 1.0; d <= gapProbe; d += 1) {
      for (final x in [position.dx + d, position.dx - d]) {
        if (x < 0 || x > maxX) continue;
        if (super.hitTest(result, position: Offset(x, position.dy))) {
          return true;
        }
      }
    }
    return false;
  }
}

/// 囲みの一覧（語らい・寄合）で、選択中の項目を囲む枠を、選択が移る時に、次の項目へ滑らせる
/// （2026-11-26）。メニューチップの丸（`RingNavBar`）と同じ動き（0.32秒・`easeOutCubic`）。
/// 一覧のスクロールには、枠が追従する（`LayerLink`）。選択中の項目は、[RingSelectedMarker]で包む。
class RingSlideHost extends StatefulWidget {
  const RingSlideHost({required this.style, required this.child, super.key});

  final AppUiStyle style;
  final Widget child;

  static RingSlideHostState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RingSlideScope>()?.state;

  @override
  State<RingSlideHost> createState() => RingSlideHostState();
}

class _RingSlideScope extends InheritedWidget {
  const _RingSlideScope({required this.state, required super.child});

  final RingSlideHostState state;

  @override
  bool updateShouldNotify(_RingSlideScope old) => false;
}

class RingSlideHostState extends State<RingSlideHost>
    with SingleTickerProviderStateMixin {
  final LayerLink link = LayerLink();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  RenderBox? _box;
  Rect? _lastRect;
  Offset _displacement = Offset.zero;
  Size _fromSize = Size.zero;
  Size _toSize = Size.zero;
  int _mountCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Rect? _rectOf(RenderBox box) {
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.attached || !box.attached || !box.hasSize) {
      return null;
    }
    return host.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  /// 選択中の項目が、描かれた後（レイアウト済み）に呼ぶ。前の位置から、新しい位置へ滑らせる。
  void marked(RenderBox box) {
    if (!mounted) return;
    _mountCount++;
    final rect = _rectOf(box);
    final previous = _lastRect;
    _box = box;
    _lastRect = rect;
    if (rect == null) return;
    final moved =
        previous != null &&
        ((previous.topLeft - rect.topLeft).distance >= 1 ||
            previous.size != rect.size);
    setState(() {
      _toSize = rect.size;
      if (moved) {
        _displacement = previous.topLeft - rect.topLeft;
        _fromSize = previous.size;
      }
    });
    if (moved) _controller.forward(from: 0);
  }

  /// 選択中の項目が、無くなった時。同じフレームで、別の項目が選ばれなければ、位置を忘れる。
  void unmarked(RenderBox? box) {
    if (identical(_box, box)) _box = null;
    final count = _mountCount;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mountCount == count && _box == null) _lastRect = null;
    });
  }

  /// スクロールなどで、選択中の項目の位置が動いた時に、覚えている位置を更新する。
  void _refresh() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final box = _box;
      if (!mounted || box == null) return;
      _lastRect = _rectOf(box) ?? _lastRect;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _RingSlideScope(
      state: this,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _refresh();
              return false;
            },
            child: widget.child,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t = Curves.easeOutCubic.transform(
                          _controller.value,
                        );
                        final size = Size.lerp(_fromSize, _toSize, t);
                        final animating = _controller.isAnimating;
                        return CompositedTransformFollower(
                          link: link,
                          showWhenUnlinked: false,
                          offset: animating
                              ? _displacement * (1 - t)
                              : Offset.zero,
                          child: animating && size != null
                              ? SizedBox(
                                  width: size.width,
                                  height: size.height,
                                  child: RingOutline(style: widget.style),
                                )
                              : _RingToTargetSize(style: widget.style),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 選択中の項目の大きさに合わせて枠を描く（滑っていない時）。大きさは、項目側が、[RingSlideHost]へ渡す。
class _RingToTargetSize extends StatelessWidget {
  const _RingToTargetSize({required this.style});

  final AppUiStyle style;

  @override
  Widget build(BuildContext context) {
    final state = RingSlideHost.maybeOf(context);
    final size = state?._toSize ?? Size.zero;
    if (size.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: size.width,
      height: size.height,
      child: RingOutline(style: style),
    );
  }
}

/// 囲みの一覧の、選択中の項目を包む。[RingSlideHost]の中なら、枠を、選択が移る時に滑らせる。
/// 外なら、その場に枠を重ねる（滑らない）。
class RingSelectedMarker extends StatefulWidget {
  const RingSelectedMarker({
    required this.style,
    required this.child,
    super.key,
  });

  final AppUiStyle style;
  final Widget child;

  @override
  State<RingSelectedMarker> createState() => _RingSelectedMarkerState();
}

class _RingSelectedMarkerState extends State<RingSelectedMarker> {
  RingSlideHostState? _host;
  RenderBox? _box;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host = RingSlideHost.maybeOf(context);
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(RingSelectedMarker old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final host = _host;
      final box = context.findRenderObject();
      if (!mounted || host == null || box is! RenderBox) return;
      _box = box;
      host.marked(box);
    });
  }

  @override
  void dispose() {
    _host?.unmarked(_box);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) {
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(child: RingOutline(style: widget.style)),
          ),
        ],
      );
    }
    return CompositedTransformTarget(link: host.link, child: widget.child);
  }
}
