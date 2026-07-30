import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_shapes.dart';

/// 劇画スタイルの色付きバッジ（アイコン背後のブロック）を描く。
/// 参考スケッチの形（正方形ではなく、左上に鋭い頂点・右側に大きく
/// 張り出す頂点・下に底の頂点・左に頂点を持つ、旗/凧のような非対称の
/// 四角形）を直線の辺でなぞり、外側から黒い太枠→白い縁取り→イメージ
/// カラーの塗り、という3層の同心図形として描く。
/// 凸四角形にしているのは、[insetPolygon]の辺オフセット計算が凹んだ
/// 頂点があると縁の太さが不均一・破綻しやすいため（前回、頂点を1つ
/// 内側に窪ませて凹四角形にした結果、白い縁取りがほぼ潰れて見えなく
/// なる不具合が発生した）。
/// （2026-07-30、chat_screen.dartの`_GekigaBadgePainter`から移動・公開化。
/// メッセージ画面のアイコン背後だけでなく、ホーム画面のナビチップ等
/// アプリ全体で同じ意匠を再利用するための共通部品）。
class GekigaBadgePainter extends CustomPainter {
  const GekigaBadgePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = [
      Offset(size.width * 0.0, size.height * 0.3),
      Offset(size.width * 0.97, size.height * 0.42),
      Offset(size.width * 0.55, size.height * 0.98),
      Offset(size.width * 0.0, size.height * 0.55),
    ];
    final white = insetPolygon(outer, 4.5);
    final fill = insetPolygon(outer, 8);

    canvas.drawPath(pathFromPoints(outer), Paint()..color = Colors.black);
    canvas.drawPath(pathFromPoints(white), Paint()..color = Colors.white);
    canvas.drawPath(pathFromPoints(fill), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant GekigaBadgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// バッジの上に子ウィジェットを右上寄せで重ねる合成ウィジェット
/// （旧 chat_screen.dartの`_GekigaAvatarFrame`、そのまま移動）。
/// メッセージ画面のアイコン背後に使う。
class GekigaBadgeFrame extends StatelessWidget {
  const GekigaBadgeFrame({
    required this.child,
    required this.badgeColor,
    required this.seed,
    super.key,
  });

  final Widget child;
  final Color badgeColor;
  final int seed;

  @override
  Widget build(BuildContext context) {
    // 56×56の箱に対し、アバターは右上にわずかにはみ出す形で重ねる。
    // 参考スケッチのように色ブロックは正方形寄りの大きめのサイズにし、
    // 左下に色ブロックの表示面積が確保されるよう、アバターを右上へ寄せる。
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GekigaBadgePainter(color: badgeColor, seed: seed),
            ),
          ),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// バッジ形そのものだけを、正方形の箱いっぱいに描く軽量ラッパー。
/// [GekigaBadgeFrame]の「右上に重ねる」レイアウトを持たない版
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
          child: CustomPaint(painter: GekigaBadgePainter(color: color, seed: seed)),
        ),
        ?child,
      ],
    );
  }
}
