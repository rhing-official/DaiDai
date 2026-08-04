import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_shapes.dart';

/// 劇画スタイルの色付きバッジ（アイコン背後のブロック）を描く。
/// 外側から黒い太枠→白い縁取り→イメージカラーの塗り、という3層の同心
/// 図形として描く点は変わらないが、形自体は正方形の各辺を手描き風に
/// ジグザグ揺らした[handDrawnPolygonPath]ベースに統一している
/// （2026-08-03、旧: 直線縁取りの非対称な旗/凧型四角形から変更。
/// `GekigaIconBadge`/`GekigaPanelBox`/テキスト欄/吹き出し等、アプリ全体の
/// 他の劇画パーツと同じジグザグ意匠に揃えるため）。3層とも同じ[seed]で
/// ジグザグ化することで、バラバラな揺れではなく同心状に連動して見える
/// ようにしている。
class GekigaBadgePainter extends CustomPainter {
  const GekigaBadgePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final white = insetPolygon(outer, 4.5);
    final fill = insetPolygon(outer, 8);

    const jitter = 2.2;
    const segmentsPerEdge = 4;
    canvas.drawPath(
      handDrawnPolygonPath(
        outer,
        seed,
        jitter: jitter,
        segmentsPerEdge: segmentsPerEdge,
      ),
      Paint()..color = Colors.black,
    );
    canvas.drawPath(
      handDrawnPolygonPath(
        white,
        seed,
        jitter: jitter,
        segmentsPerEdge: segmentsPerEdge,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawPath(
      handDrawnPolygonPath(
        fill,
        seed,
        jitter: jitter,
        segmentsPerEdge: segmentsPerEdge,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant GekigaBadgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// バッジ形そのものだけを、正方形の箱いっぱいに描く軽量ラッパー
/// （2026-07-30新規、home_screen.dartのナビチップ用。アバターではなく
/// アイコン1つを中央に乗せたい場面で使う）。
class GekigaBadgeShape extends StatelessWidget {
  const GekigaBadgeShape({
    required this.color,
    required this.seed,
    this.child,
    super.key,
  });

  final Color color;
  final int seed;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: GekigaBadgePainter(color: color, seed: seed),
          ),
        ),
        ?child,
      ],
    );
  }
}
