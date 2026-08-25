import 'package:flutter/material.dart';

import '../../theme/dessin/dessin_colors.dart';

/// 設定タブのUIスタイル選択肢（[_UiStyleFolder]）のデッサンUI版プレビュー
/// タイル。手描き風の輪郭線はCustomPainterでは鉛筆画らしく見えなかったため
/// （2026-08-25）、細い実線の枠で囲むだけのミニマルな見た目にしている。
class DessinOptionTile extends StatelessWidget {
  const DessinOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.seed,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// 現在の描画では使わないが、呼び出し元とのシグネチャ互換のため残す。
  final int seed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? DessinColors.paperShade : DessinColors.paper,
          border: Border.all(color: DessinColors.ink),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: DessinColors.ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: DessinColors.ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: DessinColors.graphite,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
