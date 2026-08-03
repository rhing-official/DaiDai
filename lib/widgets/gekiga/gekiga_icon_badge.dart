import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';

/// 劇画スタイルの「＋」ボタン・歯車アイコン等、単体アイコンを手描き風の
/// ギザギザ枠で囲む小さな正方形バッジ。[GekigaPanelBox]（可変幅の行）とは
/// 別に、常に正方形を保ちたいアイコン単体向けの実装として用意する
/// （2026-08-03新規）。タップ処理は持たないので、呼び出し側で`InkWell`等の
/// タップ領域と組み合わせて使う（アイコンボタンをそのまま置き換える形）。
class GekigaIconBadge extends StatelessWidget {
  const GekigaIconBadge({
    required this.icon,
    this.size = 36,
    this.seed = 0,
    super.key,
  });

  final IconData icon;
  final double size;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GekigaIconBadgePainter(seed: seed),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: GekigaColors.onPanel, size: size * 0.6),
      ),
    );
  }
}

/// [GekigaIconBadge]にタップ処理を組み合わせた、標準の`IconButton`の
/// 劇画スタイル置き換え版（2026-08-03新規）。「寄合を追加」「広場自体の
/// 設定」等、一対・広場・寄合一覧まわりの単体アイコンボタン全般で使う。
class GekigaIconButton extends StatelessWidget {
  const GekigaIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: GekigaIconBadge(icon: icon, size: size, seed: icon.hashCode),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _GekigaIconBadgePainter extends CustomPainter {
  const _GekigaIconBadgePainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final path = handDrawnPolygonPath(
      [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ],
      seed,
      // アイコン1個だけの小さな面積なので、パネル（jitter: 2.4）より
      // さらに控えめにしてアイコンの視認性を損なわないようにする。
      jitter: 1.6,
      segmentsPerEdge: 4,
    );
    canvas.drawPath(path, Paint()..color = GekigaColors.panel);
    canvas.drawPath(
      path,
      Paint()
        ..color = GekigaColors.onPanel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GekigaIconBadgePainter oldDelegate) =>
      oldDelegate.seed != seed;
}
