import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/accent_color_provider.dart';
import '../../theme/glass/glass_theme_extras.dart';
import '../../theme/text_prominence_colors.dart';

/// ガラスUI用のAppBar。スクロールするコンテンツが下に透けて見えるよう
/// [flexibleSpace]に`BackdropFilter`をかける。上端固定のバーのため
/// [GlassSurface]は使わず、下端のみに光彩線を描く専用実装にしている。
class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBar({
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.bottom,
    super.key,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentColorProvider);
    final extras =
        Theme.of(context).extension<GlassThemeExtras>() ??
        const GlassThemeExtras(
          chromeBlurSigma: 20,
          floatingBlurSigma: 24,
          chromeTintAlpha: 0.55,
          floatingTintAlpha: 0.6,
          cardTintAlpha: 0.72,
          edgeBorderBaseAlpha: 0.28,
          edgeBorderHighlightAlpha: 0.65,
          textTertiary: TextProminence.lightTertiary,
        );
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: bottom,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: extras.chromeBlurSigma,
            sigmaY: extras.chromeBlurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(
                alpha: extras.chromeTintAlpha,
              ),
              border: Border(
                bottom: BorderSide(
                  color: accent.withValues(
                    alpha: extras.edgeBorderHighlightAlpha,
                  ),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
