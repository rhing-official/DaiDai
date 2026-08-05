import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_shapes.dart';
import 'monochrome_box.dart';

/// メッセージ画面の送信者アイコンを、劇画UI専用のモノクロボックス
/// （直線のみの不規則四角形、細い白枠＋太い黒枠の二重枠）でクリップして
/// 見せるウィジェット（2026-08-05新規、以降複数回再実装）。参考画像の
/// 指摘により、4つの角の角度をそれぞれ変える: 左下はほぼ直角、右下は
/// やや鈍角、右上はほぼ直角〜やや鈍角、左上は他の角より外側（左上方向）
/// に伸びていて鋭角、という不規則な形（[monochromeBoxVertices]参照）。
class GekigaPhotoFrame extends StatelessWidget {
  const GekigaPhotoFrame({
    this.image,
    this.fallback,
    this.size = 32,
    super.key,
  });

  final ImageProvider? image;
  final Widget? fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final overflow = size * monochromeBoxOverflowRatio;
    final vertices = monochromeBoxVertices(size, size, overflow: overflow);

    // 左上角の突き出し（[overflow]）分だけ外側に余白を確保してから本体を
    // 描く（2026-08-05追加）。この余白が無いと、突き出した部分がメッセージ
    // 一覧の1つ上の項目に重なって見えてしまう（Stackのclip無し描画は
    // 呼び出し側のレイアウト上の占有サイズには影響しないため）。形自体
    // （[monochromeBoxVertices]の計算）は変えず、確保する領域だけ広げて
    // 描画位置を右下へずらしている。
    return Padding(
      padding: EdgeInsets.only(left: overflow, top: overflow),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            monochromeBoxExtend(
              width: size,
              height: size,
              overflow: overflow,
              child: CustomPaint(
                painter: MonochromeBoxPainter(
                  vertices: vertices,
                  thicknessBase: size,
                ),
              ),
            ),
            monochromeBoxExtend(
              width: size,
              height: size,
              overflow: overflow,
              child: ClipPath(
                clipper: MonochromeBoxClipper(
                  vertices: vertices,
                  inset: size * 0.15,
                ),
                child: image != null
                    ? Image(image: image!, fit: BoxFit.cover)
                    : (fallback ?? const SizedBox.shrink()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
