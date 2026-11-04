import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

/// 「吸い込み」遷移の液状化（波打ち＋右下への渦状のすぼまり、2026-11-04、初版）。
/// 子の描画結果を`shaders/liquify.frag`で歪める。
///
/// **ウィジェット木の形は常に同じ**（[enabled]がfalseの間は[AnimatedSampler]が
/// 子をそのまま描く）。有無で木の形が変わると、子の画面全体が再マウントされるため。
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
