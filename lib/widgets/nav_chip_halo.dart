import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/nav_chip_band_provider.dart';

/// メニューチップの帯の周りで、[child]を透明へ滲ませる（2026-11-29）。
///
/// 「アイコン+寄合一覧」で、アイコン列を画面の下端まで伸ばすと、列のアイコンが下端の
/// メニューチップの下へ潜り込み、重なって見分けにくい。チップの帯を囲む角丸の形を、
/// ぼかして[child]から抜く。チャットの入力欄の周りの滲み（`ChatEdgeFade`）と同じく、背景色を
/// 重ねず、アルファだけを落とすので、背景が単色・画像・ガラスのどれでも破綻しない。
/// 全UIスタイル共通。チップの帯が[child]に重ならない時は、何も描き足さない。
class NavChipHalo extends ConsumerWidget {
  const NavChipHalo({
    required this.child,
    this.enabled = true,
    this.reach = defaultReach,
    super.key,
  });

  final Widget child;

  /// falseの間は滲ませない（子の木の形を変えずに切り替える為）。
  final bool enabled;

  /// チップの縁から、滲みが外へ広がる長さ。
  final double reach;

  /// 既定の広がり。チップの縁から、アイコン1個の半分ほど。
  static const double defaultReach = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final band = enabled ? ref.watch(navChipBandRectProvider) : null;
    return _HaloPaint(bandGlobal: band, reach: reach, child: child);
  }
}

class _HaloPaint extends SingleChildRenderObjectWidget {
  const _HaloPaint({
    required this.bandGlobal,
    required this.reach,
    required super.child,
  });

  final Rect? bandGlobal;
  final double reach;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHalo(bandGlobal, reach);

  @override
  void updateRenderObject(BuildContext context, _RenderHalo renderObject) {
    renderObject
      ..bandGlobal = bandGlobal
      ..reach = reach;
  }
}

class _RenderHalo extends RenderProxyBox {
  _RenderHalo(this._bandGlobal, this._reach);

  Rect? _bandGlobal;
  double _reach;

  set bandGlobal(Rect? value) {
    if (_bandGlobal == value) return;
    _bandGlobal = value;
    markNeedsPaint();
  }

  set reach(double value) {
    if (_reach == value) return;
    _reach = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final band = _bandGlobal;
    final child = this.child;
    if (child == null) return;
    if (band == null) {
      context.paintChild(child, offset);
      return;
    }
    // チップの帯を、この部品の座標へ直す。
    final origin = localToGlobal(Offset.zero);
    final local = band.shift(-origin);
    // 滲みの外へはみ出す分（ぼかしの裾）まで含めて、重ならなければそのまま描く。
    final bounds = offset & size;
    final halo = local.shift(offset).inflate(_reach);
    if (!halo.overlaps(bounds)) {
      context.paintChild(child, offset);
      return;
    }
    // 帯の角丸は、チップの丸（半径=高さの半分）に合わせ、そこへ余白を足す。
    final core = local.shift(offset).inflate(_reach * 0.5);
    final rrect = RRect.fromRectAndRadius(
      core,
      Radius.circular(core.shortestSide / 2),
    );
    final canvas = context.canvas;
    canvas.saveLayer(bounds.inflate(_reach), Paint());
    context.paintChild(child, offset);
    canvas.drawRRect(
      rrect,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFF000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _reach * 0.6),
    );
    canvas.restore();
  }
}
