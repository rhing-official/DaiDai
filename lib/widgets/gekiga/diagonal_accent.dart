import 'package:flutter/material.dart';

/// 画面を斜めに横切る大きな帯状の装飾。参考画像の「巨大な赤いシェブロン」
/// を再現する、単純な矩形の回転塗りつぶし（2026-07-30新規）。
class DiagonalAccentPainter extends CustomPainter {
  const DiagonalAccentPainter({
    required this.color,
    this.thickness = 0.35, // sizeの短辺に対する帯の太さの割合
    this.angle = -0.35, // ラジアン。負値で右肩上がり
  });

  final Color color;
  final double thickness;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-size.width / 2, -size.height / 2);
    final band = size.shortestSide * thickness;
    final rect = Rect.fromLTWH(
      -size.width,
      size.height / 2 - band / 2,
      size.width * 3,
      band,
    );
    canvas.drawRect(rect, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DiagonalAccentPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.thickness != thickness ||
      oldDelegate.angle != angle;
}

/// [DiagonalAccentPainter]を敷くだけの便利ウィジェット。装飾専用なので
/// IgnorePointerで包み、下の実コンテンツへのタップ・ドラッグを奪わない。
class DiagonalAccent extends StatelessWidget {
  const DiagonalAccent({
    required this.color,
    this.thickness = 0.35,
    this.angle = -0.35,
    super.key,
  });

  final Color color;
  final double thickness;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: DiagonalAccentPainter(
            color: color,
            thickness: thickness,
            angle: angle,
          ),
        ),
      ),
    );
  }
}
