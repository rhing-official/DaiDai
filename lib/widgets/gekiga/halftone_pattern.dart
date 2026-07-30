import 'package:flutter/material.dart';

/// 規則的なドットのグリッドを敷き詰めるハーフトーン風の背景テクスチャ。
/// 静的な装飾（アニメーションしない）として使うことを想定し、paintは
/// 呼ばれるたびに同じ結果になる純粋な描画のみ行う（2026-07-30新規）。
class HalftonePainter extends CustomPainter {
  const HalftonePainter({
    required this.color,
    this.spacing = 14,
    this.dotRadius = 2.2,
    this.fadeDirection,
  });

  final Color color;
  final double spacing;
  final double dotRadius;

  /// nullなら濃度は一定。指定すると、[fadeDirection]方向に沿って
  /// 密→疎（アルファを1→0へ線形補間）にフェードする
  /// （参考画像の「キャラクターシルエット背後で密度が抜けていく」表現用）。
  final AlignmentGeometry? fadeDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final fadeStart = fadeDirection?.resolve(TextDirection.ltr).alongSize(size);
    final fadeVector =
        fadeStart == null ? null : Offset(size.width, size.height) - fadeStart;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        var alpha = 1.0;
        if (fadeStart != null &&
            fadeVector != null &&
            fadeVector.distanceSquared > 0) {
          final rel = Offset(x, y) - fadeStart;
          final t = (rel.dx * fadeVector.dx + rel.dy * fadeVector.dy) /
              fadeVector.distanceSquared;
          alpha = 1 - t.clamp(0.0, 1.0);
        }
        if (alpha <= 0.02) continue;
        canvas.drawCircle(
          Offset(x, y),
          dotRadius,
          paint..color = color.withValues(alpha: color.a * alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant HalftonePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.spacing != spacing ||
      oldDelegate.dotRadius != dotRadius ||
      oldDelegate.fadeDirection != fadeDirection;
}

/// [HalftonePainter]をSizedBox.expand越しに敷くだけの便利ウィジェット。
/// IgnorePointerで包み、下の実コンテンツへのタップ・ドラッグを一切奪わない
/// （装飾専用のレイヤーが既存のジェスチャー処理と衝突しないようにするため
/// 必須）。
class HalftoneBackground extends StatelessWidget {
  const HalftoneBackground({
    required this.color,
    this.spacing = 14,
    this.dotRadius = 2.2,
    this.fadeDirection,
    super.key,
  });

  final Color color;
  final double spacing;
  final double dotRadius;
  final AlignmentGeometry? fadeDirection;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: HalftonePainter(
            color: color,
            spacing: spacing,
            dotRadius: dotRadius,
            fadeDirection: fadeDirection,
          ),
        ),
      ),
    );
  }
}
