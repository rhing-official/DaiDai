import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import 'gekiga_badge.dart';

/// 劇画スタイルの「＋」ボタン・歯車アイコン等、単体アイコンをモノクロ
/// ボックス（[GekigaBadgeShape]参照）で囲む小さな正方形バッジ
/// （2026-08-03新規、2026-08-05に直線・モノクロボックス版へ変更）。
/// タップ処理は持たないので、呼び出し側で`InkWell`等のタップ領域と
/// 組み合わせて使う（アイコンボタンをそのまま置き換える形）。
class GekigaIconBadge extends StatelessWidget {
  const GekigaIconBadge({required this.icon, this.size = 36, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GekigaBadgeShape(
        color: GekigaColors.panel,
        seed: icon.hashCode,
        child: Icon(icon, color: GekigaColors.onPanel, size: size * 0.6),
      ),
    );
  }
}

/// [GekigaIconBadge]にタップ処理を組み合わせた、標準の`IconButton`の
/// 劇画スタイル置き換え版（2026-08-03新規）。「寄合を追加」「広場自体の
/// 設定」等、一対・広場・寄合一覧まわりの単体アイコンボタン全般で使う。
class GekigaIconButton extends StatelessWidget {
  const GekigaIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: GekigaIconBadge(icon: icon, size: size),
      ),
    );
  }
}
