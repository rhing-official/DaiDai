import 'dart:math' as math;
import 'dart:ui' as ui;

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

  /// 滲みの形を描いたマスク画像（不透明な面から、ぼかした角丸を抜いたもの）と、その作り元。
  /// 帯の位置・大きさが変わらない間は、作り直さない。
  ui.Image? _mask;
  ({Size size, RRect rrect, double reach})? _maskKey;

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
  bool get alwaysNeedsCompositing => child != null && _bandGlobal != null;

  @override
  void dispose() {
    _mask?.dispose();
    _mask = null;
    layer = null;
    super.dispose();
  }

  /// 帯の範囲（この部品の座標）から、マスク画像を作る。画像の透明度は、帯の中で0、離れた所で1。
  ui.Image _maskFor(Size size, RRect rrect) {
    final key = (size: size, rrect: rrect, reach: _reach);
    if (_mask != null && _maskKey == key) return _mask!;
    _mask?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFF000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _reach * 0.6),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, size.width.ceil()),
      math.max(1, size.height.ceil()),
    );
    picture.dispose();
    _mask = image;
    _maskKey = key;
    return image;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final band = _bandGlobal;
    final child = this.child;
    if (child == null) return;
    if (band == null || size.isEmpty) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    // チップの帯を、この部品の座標へ直す。
    final local = band.shift(-localToGlobal(Offset.zero));
    // 滲みの裾まで含めて、重ならなければそのまま描く。
    if (!local.inflate(_reach).overlaps(Offset.zero & size)) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    // 帯の角丸は、チップの丸（半径=高さの半分）に合わせ、そこへ余白を足す。
    final core = local.inflate(_reach * 0.5);
    final rrect = RRect.fromRectAndRadius(
      core,
      Radius.circular(core.shortestSide / 2),
    );
    final image = _maskFor(size, rrect);
    // `ShaderMask`と同じ作り。子が別のレイヤーを作っても壊れないよう、`canvas`ではなくレイヤーで掛ける。
    layer = (layer as ShaderMaskLayer?)
      ?..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      )
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer ??= ShaderMaskLayer(
      shader: ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      ),
      maskRect: offset & size,
      blendMode: BlendMode.dstIn,
    );
    context.pushLayer(layer!, super.paint, offset);
  }
}
