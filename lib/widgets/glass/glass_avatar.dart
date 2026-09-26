import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// アイコン未設定時のプレースホルダーを含め、住人・広場等のアイコンを
/// ガラスUI調の円形マテリアルで表示する（`GekigaPhotoFrame`のガラス版、
/// 2026-09-16新規）。画像の有無に関わらず同じ`GlassSurface`（縁の光彩・
/// `GlassVariant.card`）で包むことで、フラット版（`chat_screen.dart`の
/// `_SenderAvatar`、細い枠線付きの円）が画像有無に関わらず同じ枠を
/// 使っているのと同じ一貫性を持たせる。
class GlassAvatar extends StatelessWidget {
  const GlassAvatar({this.image, this.fallback, this.size = 40, super.key});

  final ImageProvider? image;
  final Widget? fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GlassSurface(
        variant: GlassVariant.card,
        borderRadius: BorderRadius.circular(size / 2),
        child: ClipOval(
          child: image != null
              ? Image(
                  image: image!,
                  // 明示サイズを指定しないと、`GlassSurface`内の`Stack`が
                  // 緩い（loose）制約しか渡さないため、正方形でない画像は
                  // 本来のアスペクト比を保った（size×sizeより小さい）ボックス
                  // として描画され、円の一部が透明のまま残ってしまっていた
                  // （フラット版`_SenderAvatar`はContainerの明示サイズで
                  // タイトな制約が伝わるため発生しない、2026-09-26修正）。
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                )
              : Center(child: fallback ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
