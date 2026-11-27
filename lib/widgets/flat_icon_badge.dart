import 'package:flutter/material.dart';

/// フラットの、メッセージ画面の上部のメニューなどの単体アイコンを囲む丸いバッジ。
/// ガラスの`GlassIconBadge`と同じく、アクセントカラーの線で囲む（2026-11-27）。塗りは背景と同じ色。
/// タップ処理は持たない。`IconButton`の`icon`に渡す。
class FlatIconBadge extends StatelessWidget {
  const FlatIconBadge({required this.icon, this.size = 32, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary),
      ),
      child: Center(
        child: Icon(icon, size: size * 0.6, color: scheme.onSurface),
      ),
    );
  }
}
