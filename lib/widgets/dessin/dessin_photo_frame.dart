import 'package:flutter/material.dart';

import '../../theme/dessin/dessin_colors.dart';

/// メッセージ画面の送信者アイコンを、デッサンUI専用の細い実線の枠で囲んで
/// 見せるウィジェット（劇画UIの`GekigaPhotoFrame`に相当）。手描き風の輪郭線
/// はCustomPainterでは鉛筆画らしく見えなかったため（2026-08-25）、通常の
/// `CircleAvatar`に細い枠を足すだけのミニマルな見た目にしている。
class DessinPhotoFrame extends StatelessWidget {
  const DessinPhotoFrame({
    required this.seed,
    this.image,
    this.fallback,
    this.size = 32,
    super.key,
  });

  final ImageProvider? image;
  final Widget? fallback;
  final double size;

  /// 現在の描画では使わないが、呼び出し元とのシグネチャ互換のため残す。
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: DessinColors.ink),
      ),
      child: ClipOval(
        child: image != null
            ? Image(image: image!, fit: BoxFit.cover)
            : (fallback ?? const SizedBox.shrink()),
      ),
    );
  }
}
