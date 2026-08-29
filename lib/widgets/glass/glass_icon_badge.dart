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
    this.shadow = false,
    super.key,
  });

  final IconData icon;
  final double size;

  /// メッセージが下から重なっても透けないようにしたい場所（ハンバーガー
  /// メニュー等）向け。[GlassSurface.opaque]参照。
  final bool opaque;

  /// ガラスUIは基本的にマテリアルへ影を使わない方針（CLAUDE.md参照）だが、
  /// ハンバーガーメニューのアイコンのみ例外的に影を残したいという要望
  /// （2026-08-30追加）に応えるためのオプトイン。`GlassSurface`自体には
  /// 影を描く仕組みを追加せず、このバッジの外側だけに個別で乗せる。
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final badge = SizedBox(
      width: size,
      height: size,
      child: GlassSurface(
        variant: GlassVariant.card,
        borderRadius: BorderRadius.circular(size / 2),
        opaque: opaque,
        child: Center(child: Icon(icon, size: size * 0.6)),
      ),
    );
    if (!shadow) return badge;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: badge,
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
    this.tooltip,
    this.opaque = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

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
              tooltip: tooltip,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
