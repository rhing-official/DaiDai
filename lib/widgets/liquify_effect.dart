import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

/// 「吸い込み」遷移の液状化（波打ち＋右下への渦状のすぼまり、2026-11-04、初版）。
/// 子の描画結果を`shaders/liquify.frag`で歪める。
///
/// **ウィジェット木の形は常に同じ**（[enabled]がfalseの間は[AnimatedSampler]が
/// 子をそのまま描く）。有無で木の形が変わると、子の画面全体が再マウントされる為。
/// シェーダーの読み込み前・失敗時も、子をそのまま描く（遷移は壊さない）。
class LiquifyEffect extends StatefulWidget {
  const LiquifyEffect({
    required this.progress,
    required this.enabled,
    required this.child,
    super.key,
  });

  /// 0（通常）〜1（吸い込み切る）。
  final double progress;
  final bool enabled;
  final Widget child;

  @override
  State<LiquifyEffect> createState() => _LiquifyEffectState();
}

class _LiquifyEffectState extends State<LiquifyEffect> {
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  ui.FragmentShader? _shader;

  static Future<ui.FragmentProgram?> _load() {
    return _loading ??= ui.FragmentProgram.fromAsset('shaders/liquify.frag')
        .then<ui.FragmentProgram?>((program) => _program = program)
        .catchError((Object error) {
          debugPrint('LiquifyEffect: シェーダーの読み込みに失敗: $error');
          return null;
        });
  }

  @override
  void initState() {
    super.initState();
    _shader = _program?.fragmentShader();
    if (_shader == null) {
      _load().then((program) {
        if (!mounted || program == null) return;
        setState(() => _shader = program.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final progress = widget.progress.clamp(0.0, 1.0);
    return AnimatedSampler(
      (image, size, canvas) {
        if (shader == null) return;
        shader
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, progress)
          ..setImageSampler(0, image);
        canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      },
      // 読み込み前（shaderがnull）はサンプラーを無効にして子をそのまま描く。
      enabled: widget.enabled && shader != null && progress > 0,
      child: widget.child,
    );
  }
}

/// 子を、**画面の隅**（[corner]、画面全体に対する位置）を基点に拡大縮小する（2026-11-05）。
/// ダイアログ・ポップアップが「アルバムの右下」ではなく「画面の右下」から現れ／へ吸い込まれる
/// ようにする為。`Transform`の`alignment`は子の枠に対する位置の為、画面の隅（枠の外）を
/// 基点に出来ない。描画時に子の画面上の位置から基点を求める。回転はしない前提。
class ScreenCornerScale extends SingleChildRenderObjectWidget {
  const ScreenCornerScale({
    required this.scale,
    this.corner = Alignment.bottomRight,
    super.child,
    super.key,
  });

  final double scale;
  final Alignment corner;

  /// 画面（ウィンドウ）全体の大きさ。`MediaQuery`はペインなどが上書きして小さくしている
  /// ことがあり、基点が本物の画面の隅からずれる為、`View`から直接求める。
  static Size _viewSize(BuildContext context) {
    final view = View.of(context);
    return view.physicalSize / view.devicePixelRatio;
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScreenCornerScale(scale, corner, _viewSize(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderScreenCornerScale)
      ..scale = scale
      ..corner = corner
      ..screenSize = _viewSize(context);
  }
}

class _RenderScreenCornerScale extends RenderProxyBox {
  _RenderScreenCornerScale(this._scale, this._corner, this._screenSize);

  double _scale;
  Alignment _corner;
  Size _screenSize;

  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
  }

  set corner(Alignment value) {
    if (_corner == value) return;
    _corner = value;
    markNeedsPaint();
  }

  set screenSize(Size value) {
    if (_screenSize == value) return;
    _screenSize = value;
    markNeedsPaint();
  }

  /// 基点（画面の隅）を、この子のローカル座標で表したもの。
  Offset _originLocal() {
    final global = Offset(
      (_corner.x + 1) / 2 * _screenSize.width,
      (_corner.y + 1) / 2 * _screenSize.height,
    );
    return global - localToGlobal(Offset.zero);
  }

  Matrix4 _matrix() {
    final o = _originLocal();
    return Matrix4.identity()
      ..translateByDouble(o.dx, o.dy, 0.0, 1.0)
      ..scaleByDouble(_scale, _scale, 1.0, 1.0)
      ..translateByDouble(-o.dx, -o.dy, 0.0, 1.0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_scale == 1.0) {
      context.paintChild(child!, offset);
      return;
    }
    final matrix = _matrix();
    layer = context.pushTransform(
      needsCompositing,
      offset,
      matrix,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale != 1.0) transform.multiply(_matrix());
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_scale == 1.0) return super.hitTestChildren(result, position: position);
    return result.addWithPaintTransform(
      transform: _matrix(),
      position: position,
      hitTest: (result, position) =>
          child?.hitTest(result, position: position) ?? false,
    );
  }
}
