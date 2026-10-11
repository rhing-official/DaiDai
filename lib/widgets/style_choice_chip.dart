import 'package:flutter/material.dart';

import '../models/app_ui_style.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'glass/glass_surface.dart';

/// 選択式のチップ（権限管理のロール選択、管理画面の状態絞り込み等で共通）。
/// 素の`ChoiceChip`はM3既定の青緑系の選択色が出てしまうため、UIスタイルごとに既存の選択表現へ揃える
/// （フラット=アクセントカラー塗り、ガラス=`NavChip`と同じ半透明の塗り、
/// 劇画=選択は白地黒字・未選択は黒地白字。いずれもチェックマークは出さない）。
class StyleChoiceChip extends StatelessWidget {
  const StyleChoiceChip({
    super.key,
    required this.uiStyle,
    required this.selected,
    required this.onTap,
    required this.labelBuilder,
    this.expand = false,
  });

  final AppUiStyle uiStyle;
  final bool selected;
  final VoidCallback onTap;

  /// 文字色（選択状態・スタイルに応じた固定のコントラスト色）を受け取って中身を作る。
  final Widget Function(Color foreground) labelBuilder;

  /// 縦に並べる一覧用に、親の横幅いっぱいに広げて中身を左寄せにする。
  final bool expand;

  static const _padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);

  Widget _content(Color fg) {
    final label = labelBuilder(fg);
    return Padding(
      padding: _padding,
      child: expand
          ? SizedBox(
              width: double.infinity,
              child: Align(alignment: Alignment.centerLeft, child: label),
            )
          : label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (uiStyle) {
      case AppUiStyle.gekiga:
        final fill = selected ? GekigaColors.onPanel : GekigaColors.panel;
        final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
        return Material(
          color: fill,
          shape: const RoundedRectangleBorder(),
          child: InkWell(onTap: onTap, child: _content(fg)),
        );
      case AppUiStyle.glass:
        const radius = BorderRadius.all(Radius.circular(20));
        return GlassSurface(
          borderRadius: radius,
          child: Material(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.45)
                : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: _content(colorScheme.onSurfaceVariant),
            ),
          ),
        );
      default:
        final fg = selected
            ? colorScheme.onPrimary
            : colorScheme.onSurfaceVariant;
        return Material(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: _content(fg),
          ),
        );
    }
  }
}
