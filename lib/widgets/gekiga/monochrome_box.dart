import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_shapes.dart';

/// [monochromeBoxVertices]の頂点で、黒の外枠→白の内枠という2層の塗りを
/// 描く共通ペインター。[fillColor]を指定すると、さらに内側に3層目の塗りを
/// 追加する（[GekigaBadgePainter]のような色付きバッジ用、2026-08-05新規、
/// 旧ジグザグ版`GekigaBadgePainter`/`_GekigaIconBadgePainter`等の直線・
/// モノクロ版としての共通化）。
///
/// [seed]を指定すると、枠の太さ（黒外枠・白内枠の厚み）を箱ごとに僅かに
/// 変化させる（2026-08-05追加。角の形を変える代わりに、直角の箱のまま
/// 「些細な手作り感」を出す手段として採用。`seed`が同じなら常に同じ太さに
/// なり、再描画のたびに変わることはない）。変化の範囲は既定の太さを上限に
/// 0.7〜1.0倍のみ（薄くなる方向のみ）に留める。太くなる方向まで許すと、
/// 箱の内側paddingを枠が食い込んでコンテンツがはみ出す恐れがあるため。
class MonochromeBoxPainter extends CustomPainter {
  const MonochromeBoxPainter({
    required this.vertices,
    required this.thicknessBase,
    this.fillColor,
    this.seed,
  });

  final List<Offset> vertices;
  final double thicknessBase;
  final Color? fillColor;
  final int? seed;

  @override
  void paint(Canvas canvas, Size size) {
    final boxSeed = seed;
    final scale = boxSeed == null
        ? 1.0
        : 0.7 + math.Random(boxSeed).nextDouble() * 0.3;
    final white = insetPolygon(vertices, thicknessBase * 0.10 * scale);
    canvas.drawPath(pathFromPoints(vertices), Paint()..color = Colors.black);
    canvas.drawPath(pathFromPoints(white), Paint()..color = Colors.white);
    final color = fillColor;
    if (color != null) {
      final fill = insetPolygon(vertices, thicknessBase * 0.18 * scale);
      canvas.drawPath(pathFromPoints(fill), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant MonochromeBoxPainter oldDelegate) =>
      oldDelegate.vertices != vertices ||
      oldDelegate.thicknessBase != thicknessBase ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.seed != seed;
}

/// [monochromeBoxVertices]の頂点（または[inset]だけ内側に縮めた形）で
/// コンテンツをクリップする共通クリッパー（写真・テキスト入力欄の中身など、
/// 箱の内側にコンテンツを収める用途）。
class MonochromeBoxClipper extends CustomClipper<Path> {
  const MonochromeBoxClipper({required this.vertices, this.inset = 0});

  final List<Offset> vertices;
  final double inset;

  @override
  Path getClip(Size size) {
    if (inset <= 0) return pathFromPoints(vertices);
    return pathFromPoints(insetPolygon(vertices, inset));
  }

  @override
  bool shouldReclip(covariant MonochromeBoxClipper oldDelegate) =>
      oldDelegate.vertices != vertices || oldDelegate.inset != inset;
}

/// [child]を、左上角が突き出る分（[overflow]）だけ広げた[Positioned]で
/// ラップする共通ヘルパー（[overflow]が0なら元の矩形と同じ大きさのまま）。
/// 呼び出し側の親[Stack]は`clipBehavior: Clip.none`にする必要がある。
Widget monochromeBoxExtend({
  required double width,
  required double height,
  required double overflow,
  required Widget child,
}) {
  return Positioned(
    left: -overflow,
    top: -overflow,
    width: width + overflow,
    height: height + overflow,
    child: child,
  );
}
