import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// ガラスUIの「＋」ボタン・歯車アイコン等、単体アイコンをガラス調の円形
/// マテリアル（[GlassSurface]参照）で囲む小さなバッジ（2026-08-29新規、
/// `GekigaIconBadge`のガラス版）。タップ処理は持たないので、
/// `PopupMenuButton.icon`のように呼び出し側が別途タップ領域を持つ場所で使う。
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({
    required this.icon,
    this.size = 36,
    this.opaque = false,
    super.key,
  });

  final IconData icon;
  final double size;

  /// メッセージが下から重なっても透けないようにしたい場所（ハンバーガー
  /// メニュー等）向け。[GlassSurface.opaque]参照。
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GlassSurface(
        variant: GlassVariant.card,
        borderRadius: BorderRadius.circular(size / 2),
        opaque: opaque,
        child: Center(child: Icon(icon, size: size * 0.6)),
      ),
    );
  }
}

/// [GlassIconBadge]にタップ処理を組み合わせた、標準の`IconButton`の
/// ガラススタイル置き換え版（2026-08-29新規、`GekigaIconButton`のガラス版）。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.opaque = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  /// メッセージが下から重なっても透けないようにしたい場所（通話ボタン等）
  /// 向け。[GlassSurface.opaque]参照。
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GlassSurface(
        variant: GlassVariant.card,
        borderRadius: BorderRadius.circular(size / 2),
        opaque: opaque,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: Center(
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(icon, size: size * 0.6),
              tooltip: '',
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
