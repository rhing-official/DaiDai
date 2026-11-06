import 'package:flutter/material.dart';

import '../models/app_ui_style.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'gekiga/gekiga_panel_box.dart';
import 'glass/glass_surface.dart';

/// 選択式のチップ（権限管理のロール選択、管理画面の状態絞り込み等で共通）。
/// 素の`ChoiceChip`はM3既定の青緑系の選択色が出てしまうため、UIスタイル毎に既存の選択表現へ揃える
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
      case AppUiStyle.block:
        final line = BlockTheme.lineColor(Theme.of(context).brightness);
        final shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BlockTheme.radius),
          side: BorderSide(color: line, width: BlockTheme.borderWidth),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BlockTheme.radius),
            boxShadow: [
              BoxShadow(color: line, offset: const Offset(3, 3), blurRadius: 0),
            ],
          ),
          child: Material(
            color: selected
                ? colorScheme.primary
                : (Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : colorScheme.surfaceContainerHighest),
            surfaceTintColor: Colors.transparent,
            shape: shape,
            child: InkWell(
              onTap: onTap,
              customBorder: shape,
              child: _content(
                selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
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

/// 劇画の絞り込みチップの並び。語らいの「一対/広場」タブ（`CategoryTab`）と同じく、
/// 箱同士を接合した横並びのモノクロボックスで描く（選択=白地黒字・未選択=黒地白字）。
/// 他のスタイルは[StyleChoiceChip]を使う。
class GekigaChoiceChipRow extends StatelessWidget {
  const GekigaChoiceChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  final List<String> labels;
  final List<bool> selected;

  /// 押されたチップの番号。
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    // 幅に収まらなければ折り返す（他のスタイルの`Wrap`と同じ）。箱は1つずつ独立させ、
    // 間隔は接合リストと同じ[GekigaJointedTileList.gap]。
    return Wrap(
      spacing: GekigaJointedTileList.gap,
      runSpacing: GekigaJointedTileList.gap,
      children: [
        for (var i = 0; i < labels.length; i++)
          GekigaJointedTileList(
            axis: Axis.horizontal,
            seeds: [labels[i].hashCode],
            selectedFlags: [selected[i]],
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected[i]
                            ? GekigaColors.panel
                            : GekigaColors.onPanel,
                        fontSize: 16,
                        fontWeight: selected[i]
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
