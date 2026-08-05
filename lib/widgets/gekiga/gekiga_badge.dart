import 'package:flutter/material.dart';

import 'monochrome_box.dart';

/// バッジ形そのものだけを、正方形の箱いっぱいに描く軽量ラッパー
/// （2026-07-30新規、home_screen.dartのナビチップ・各種アイコンボタン用。
/// アバターではなくアイコン1つを中央に乗せたい場面で使う）。モノクロボックス
/// （直角の矩形、黒外枠→白内枠→[color]塗りの3層構成）で描く（2026-08-05、
/// メッセージ画面アイコンと同じ非対称な角＋左上の突き出しを流用していたが、
/// 些細な意匠のはずが凝った変形に見えてしまうとの指摘を受け、直角の矩形に
/// 戻した。角の変化の代わりに、[seed]を指定すると枠の太さが箱ごとに僅かに
/// 変わる（[MonochromeBoxPainter]参照））。
class GekigaBadgeShape extends StatelessWidget {
  const GekigaBadgeShape({
    required this.color,
    this.child,
    this.seed,
    super.key,
  });

  final Color color;
  final Widget? child;
  final int? seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        final vertices = [
          Offset.zero,
          Offset(size, 0),
          Offset(size, size),
          Offset(0, size),
        ];
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: MonochromeBoxPainter(
                vertices: vertices,
                thicknessBase: size,
                fillColor: color,
                seed: seed,
              ),
            ),
            ?child,
          ],
        );
      },
    );
  }
}
