import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'glass/glass_surface.dart';
import 'nav_chip.dart';

const double _kPad = 6;
const double _kBarRadius = 28;

/// 丸の直径（チップより小さい。帯の厚みを狭めた分に合わせる）。
const double _kRingSize = 46;

/// 「丸で囲む」時の、フラット・ガラス・版画・劇画のメニューチップの帯（2026-11-26）。チップを
/// 1本の帯にまとめ、選択中を、そのスタイルらしい線の丸（劇画は角の小さい四角）で囲む（塗らない）。選択が移ると、
/// 丸が次の項目へ、少し遅れて滑る。チョークは[ChalkNavBar]、和紙は[WashiNavBar]が描く。
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

    // 丸は、塗らず、アクセントカラーの線だけで囲む（劇画は白）。
    Widget ring() => switch (style) {
      AppUiStyle.glass => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 1.6),
        ),
      ),
      AppUiStyle.block => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.primary,
            width: BlockTheme.borderWidth,
          ),
        ),
      ),
      AppUiStyle.gekiga => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: GekigaColors.onPanel, width: 3),
        ),
      ),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
      ),
    };

    final target = (selectedIndex ?? -1).toDouble();
    return Stack(
      children: [
        Positioned.fill(child: barBackground()),
        TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, position, _) {
            if (position < 0) return const SizedBox.shrink();
            // 丸は、チップの中心に置く。
            final inset = (kNavChipSize - _kRingSize) / 2;
            final offset =
                _kPad + position * (kNavChipSize + kNavChipGap) + inset;
            return Positioned(
              left: vertical ? _kPad + inset : offset,
              top: vertical ? offset : _kPad + inset,
              width: _kRingSize,
              height: _kRingSize,
              child: IgnorePointer(child: ring()),
            );
          },
        ),
        Padding(padding: const EdgeInsets.all(_kPad), child: child),
      ],
    );
  }
}
