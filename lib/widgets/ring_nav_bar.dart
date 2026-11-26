import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'glass/glass_surface.dart';

const double _kPad = 12;
const double _kBarRadius = 28;

/// 「丸で囲む」時の、フラット・ガラス・版画・劇画のメニューチップの帯（2026-11-26）。チップを
/// 1本の帯にまとめる。選択中の丸（劇画は角の小さい四角）は、LiquidChipStripの水が流れ込んで
/// 塗る（この帯は背景だけを描く）。チョークは[ChalkNavBar]、和紙は[WashiNavBar]が描く。
class RingNavBar extends ConsumerWidget {
  const RingNavBar({
    required this.child,
    required this.selectedIndex,
    required this.vertical,
    super.key,
  });

  final Widget child;
  final int? selectedIndex;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final radius = BorderRadius.circular(
      style == AppUiStyle.gekiga ? 6 : _kBarRadius,
    );

    Widget barBackground() => switch (style) {
      AppUiStyle.glass => GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: radius,
        child: const SizedBox.expand(),
      ),
      AppUiStyle.block => DecoratedBox(
        decoration: BoxDecoration(
          color: brightness == Brightness.light ? Colors.white : scheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: BlockTheme.lineColor(brightness),
            width: BlockTheme.borderWidth,
          ),
          boxShadow: BlockTheme.shadow(scheme.primary, brightness),
        ),
      ),
      AppUiStyle.gekiga => DecoratedBox(
        decoration: BoxDecoration(
          color: GekigaColors.panel,
          borderRadius: radius,
          border: Border.all(color: GekigaColors.onPanel, width: 3),
        ),
      ),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: radius,
        ),
      ),
    };

    return Stack(
      children: [
        Positioned.fill(child: barBackground()),
        Padding(padding: const EdgeInsets.all(_kPad), child: child),
      ],
    );
  }
}
