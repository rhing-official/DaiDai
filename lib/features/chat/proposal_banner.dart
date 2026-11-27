import '../../widgets/kinari_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/chalk_banner.dart';
import '../../widgets/glass/glass_surface.dart';

/// 絶縁・既読オン/オフの提案バナー（`chat_panes.dart`）の共通レイアウト
/// （2026-10-11追加）。幅が[narrowBreakpoint]未満（モバイル等）ならメッセージ文と
/// ボタン群を2段（文の下に右寄せのボタン）に分け、それ以上なら1行に並べる。
///
/// 外枠（面・枠線・文字色）はUIスタイルに従う（2026-11-17、以前は全スタイル共通の
/// 薄い赤の面）。タスクバナー（`task_banner.dart`）と同じ描き分けだが、面はアクセント
/// ではなく中立色にする（赤い「同意する」ボタンとのコントラストを保つため）。
/// 文字色はここで与えるので、[message]の`Text`は色を指定しない。
class ProposalBannerLayout extends ConsumerWidget {
  const ProposalBannerLayout({
    required this.message,
    required this.actions,
    super.key,
  });

  final Widget message;
  final List<Widget> actions;

  /// ホーム・管理画面のナビチップと同じ、狭い/広いの境目。
  static const narrowBreakpoint = 600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 枠の色がボタンの波紋を覆わないよう、中身は透明なMaterialの上に置く。Materialは
    // 自前の文字スタイルを与えるため、文字色はその内側で指定する。
    Widget content(Color textColor) => Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: textColor),
        child: _content(),
      ),
    );
    switch (uiStyle) {
      case AppUiStyle.gekiga:
        return Container(
          decoration: BoxDecoration(
            color: GekigaColors.panel,
            border: Border.all(color: GekigaColors.onPanel, width: 3),
          ),
          child: content(GekigaColors.onPanel),
        );
      case AppUiStyle.glass:
        return GlassSurface(
          variant: GlassVariant.chrome,
          borderRadius: BorderRadius.zero,
          enableEdgeStroke: false,
          child: content(colorScheme.onSurface),
        );
      case AppUiStyle.chalk:
        // 塗らず、チョークの線の枠で囲む（2026-11-27）。以前は版画と同じ太い黒枠だった。
        return ChalkBannerFrame(child: content(colorScheme.onSurface));
      case AppUiStyle.block:
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isDark ? BlockTheme.darkLine : BlockTheme.lightLine,
              width: BlockTheme.borderWidth,
            ),
          ),
          child: content(colorScheme.onSurface),
        );
      case AppUiStyle.kinari:
        return KinariInset(
          color: colorScheme.surface,
          radius: 12,
          child: content(colorScheme.onSurface),
        );
      case AppUiStyle.flat:
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: content(colorScheme.onSurface),
        );
    }
  }

  Widget _content() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < narrowBreakpoint;
        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: actions,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    message,
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: buttons),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: message),
                    buttons,
                  ],
                ),
        );
      },
    );
  }
}

/// 提案バナーの「同意する」ボタン用スタイル。他の「大事な選択を確定させる
/// ボタン」と同じ固定の濃い赤＋白文字（外観・ライト/ダークに関わらず同じ。
/// `colorScheme.error`はダークで薄く、ライトで濃すぎるため使わない）。
ButtonStyle proposalAcceptButtonStyle() => FilledButton.styleFrom(
  backgroundColor: Colors.red.shade700,
  foregroundColor: Colors.white,
);
