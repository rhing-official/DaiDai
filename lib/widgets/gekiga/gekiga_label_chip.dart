import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/font_design.dart';
import '../../providers/font_design_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_fonts.dart';

/// 劇画スタイルの黒ラベルチップ。白抜き太字・角丸なしの矩形で、
/// 参考画像の「黒い帯に白文字の見出し」を再現する（2026-07-30新規）。
/// 日本語の文言が入ることを前提に、既定では専用フォント（Anton、英数字専用）
/// は使わず太字＋字間調整だけで表現する（Antonは日本語グリフを持たず、
/// 当てても結局システムフォントへフォールバックするだけで見た目が
/// 揃わないため）。ただしフォントデザイン設定で「劇画」が選ばれている
/// 場合のみ、ユーザーの明示的なオプトインとして劇画フォントを当てる
/// （英語表示時は反映され、日本語表示時は同じ理由でフォールバックする、
/// 2026-08-03追加）。
class GekigaLabelChip extends ConsumerWidget {
  const GekigaLabelChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFontDesignGekiga =
        ref.watch(fontDesignProvider) == FontDesign.gekiga;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: GekigaColors.panel,
      child: Text(
        label,
        style: TextStyle(
          color: GekigaColors.onPanel,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          fontFamily: isFontDesignGekiga ? GekigaFonts.menuFontFamily : null,
        ),
      ),
    );
  }
}
