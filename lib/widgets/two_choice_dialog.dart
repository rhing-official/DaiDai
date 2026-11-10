import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import '../theme/motion.dart';
import 'gekiga/gekiga_rect_box.dart';
import 'glass/glass_surface.dart';
import 'swipe_gestures.dart';

/// [showTwoChoiceDialog]の選択肢1つ。
class TwoChoiceOption {
  const TwoChoiceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 選ばれた時の処理。引数はこのポップアップ自身の`BuildContext`
  /// （`Navigator.of(dialogContext).pop(値)`で値を返して閉じられる）。
  final void Function(BuildContext dialogContext) onTap;
}

/// 中央の区切り線で左右に分かれた、2択の大きめのポップアップ（語らいの「＋」＝一対／広場、
/// カレンダーの「＋」＝予定／日程調整で共通、2026-11-10。以前は`talks_tab.dart`と
/// `calendar_add_choice_dialog.dart`に同じ作りが別々にあった）。
///
/// UIスタイルに沿う: フラット・ガラスは1枚のカードと細い区切り線、版画は太枠と硬い影の
/// 1つの箱と太い区切り線、劇画はギザギザの太線の1つの箱と白の区切り線。
/// 4つのスタイルで大きさは同じ。閉じる動きは設定の画面遷移に従う。
Future<T?> showTwoChoiceDialog<T>({
  required BuildContext context,
  required String barrierLabel,
  required TwoChoiceOption left,
  required TwoChoiceOption right,
}) {
  final uiStyle = ProviderScope.containerOf(context).read(appUiStyleProvider);
  final isGlass = uiStyle == AppUiStyle.glass;
  final isBoxed = uiStyle == AppUiStyle.gekiga || uiStyle == AppUiStyle.block;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      // 注意: DialogをMaterial(color: transparent)で余分に包むと、その外側Materialが
      // タップを吸収してしまいバリアの外側タップでdismissできなくなる。Dialogを直接
      // Centerの子にすること。
      final theme = Theme.of(dialogContext);
      final colorScheme = theme.colorScheme;
      final menuContent = SwipeDownToDismiss(
        onDismiss: () => Navigator.of(dialogContext).pop(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TwoChoiceTile(
                  option: left,
                  uiStyle: uiStyle,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(20),
                  ),
                ),
              ),
              VerticalDivider(
                // 劇画の枠（ギザギザの太線）の内側に収める。
                indent: uiStyle == AppUiStyle.gekiga ? 12 : 0,
                endIndent: uiStyle == AppUiStyle.gekiga ? 12 : 0,
                width: isBoxed ? 6 : 1,
                thickness: switch (uiStyle) {
                  AppUiStyle.gekiga => 3,
                  AppUiStyle.block => BlockTheme.borderWidth,
                  _ => 1,
                },
                color: switch (uiStyle) {
                  AppUiStyle.gekiga => GekigaColors.onPanel,
                  AppUiStyle.block => BlockTheme.lineColor(theme.brightness),
                  _ => colorScheme.outlineVariant,
                },
              ),
              Expanded(
                child: _TwoChoiceTile(
                  option: right,
                  uiStyle: uiStyle,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: menuContent,
      );
      if (isBoxed) {
        // 箱の影が切れないよう余白を取る。
        return Center(
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: uiStyle == AppUiStyle.gekiga
                  ? GekigaRectBox(child: content)
                  : blockMaterialBox(
                      dialogContext,
                      color: theme.brightness == Brightness.light
                          ? Colors.white
                          : colorScheme.surface,
                      child: content,
                    ),
            ),
          ),
        );
      }
      return Center(
        child: Dialog(
          backgroundColor: isGlass ? Colors.transparent : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: isGlass
              ? GlassSurface(
                  variant: GlassVariant.floating,
                  borderRadius: BorderRadius.circular(20),
                  child: content,
                )
              : content,
        ),
      );
    },
    // 設定の画面遷移の種類に従う。
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        buildDialogTransition(animation, child),
  );
}

class _TwoChoiceTile extends StatelessWidget {
  const _TwoChoiceTile({
    required this.option,
    required this.uiStyle,
    required this.borderRadius,
  });

  final TwoChoiceOption option;
  final AppUiStyle uiStyle;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isBlock = uiStyle == AppUiStyle.block;
    // 文字・アイコンはアクセントカラーにせず、背景と反対の中立色にする
    // （フラット・ガラスのアイコンだけは従来どおりアクセント）。
    final fg = isGekiga ? GekigaColors.onPanel : colorScheme.onSurface;
    final sub = isGekiga
        ? GekigaColors.onPanel.withValues(alpha: 0.75)
        : colorScheme.onSurfaceVariant;
    final neutral = isGekiga || isBlock;
    return InkWell(
      onTap: () => option.onTap(context),
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              option.icon,
              size: 40,
              color: neutral ? fg : colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              option.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: neutral ? fg : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: sub),
            ),
          ],
        ),
      ),
    );
  }
}
