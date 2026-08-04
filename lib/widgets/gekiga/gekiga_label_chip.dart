import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';

/// 劇画スタイルの黒ラベルチップ。白抜き太字・角丸なしの矩形で、
/// 参考画像の「黒い帯に白文字の見出し」を再現する（2026-07-30新規）。
/// 日本語の文言が入ることを前提に、専用フォント（Anton、英数字専用）は
/// 使わず太字＋字間調整だけで表現する（Antonは日本語グリフを持たず、
/// 当てても結局システムフォントへフォールバックするだけで見た目が
/// 揃わないため）。
class GekigaLabelChip extends StatelessWidget {
  const GekigaLabelChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: GekigaColors.panel,
      child: Text(
        label,
        style: const TextStyle(
          color: GekigaColors.onPanel,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
