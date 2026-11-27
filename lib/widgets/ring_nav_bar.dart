import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'gekiga/monochrome_box.dart';
import 'glass/glass_surface.dart';
import 'liquid_chip_highlight.dart' show glassSelectedChipFill;
import 'nav_chip.dart';

const double _kPad = 6;
const double _kBarRadius = 28;

/// 丸の直径（チップより小さい。帯の厚みを狭めた分に合わせる）。
const double _kRingSize = 46;

/// 「丸で囲む」時の、フラット・ガラス・版画・劇画のメニューチップの帯（2026-11-26）。チップを
/// 1本の帯にまとめ、選択中を、そのスタイルらしい線の丸（劇画は角の小さい四角）で囲み、同じ色で塗り潰す。選択が移ると、
/// 丸が次の項目へ、少し遅れて滑る。チョークは[ChalkNavBar]、生成りは[KinariNavBar]が描く。
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

    // 丸は、アクセントカラーの線で囲み、同じ色で塗り潰す（劇画は白）。塗りの上のアイコンは、
    // 塗りの反対色（`NavChip`が選択中のアイコンの色を切り替える、2026-11-27）。ガラスの塗りは、
    // 選択色（背景にアクセントを45%で重ねた不透明な色）にそろえる。
    Widget ring(int seed) => switch (style) {
      AppUiStyle.glass => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: glassSelectedChipFill(context),
          border: Border.all(color: scheme.primary, width: 1.6),
        ),
      ),
      AppUiStyle.block => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          border: Border.all(
            color: scheme.primary,
            width: BlockTheme.borderWidth,
          ),
        ),
      ),
      // 劇画: 選ばれた箱（白い外枠・黒い中枠・白い塗り）そのもの。液体・滑り・描きと同じ箱。
      AppUiStyle.gekiga => CustomPaint(painter: _GekigaRingPainter(seed)),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          border: Border.all(color: scheme.primary, width: 2),
        ),
      ),
    };

    final target = (selectedIndex ?? -1).toDouble();
    // 帯のスタックを、動く位置の中に置く（チップが、丸の位置から、アイコンの色を決められるように）。
    // チップ自体（[child]）は、毎回作り直さない。
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: Padding(padding: const EdgeInsets.all(_kPad), child: child),
      builder: (context, position, chips) {
        Widget? ringLayer;
        if (position >= 0) {
          // 丸は、チップの中心に置く。
          final inset = (kNavChipSize - _kRingSize) / 2;
          final offset =
              _kPad + position * (kNavChipSize + kNavChipGap) + inset;
          ringLayer = Positioned(
            left: vertical ? _kPad + inset : offset,
            top: vertical ? offset : _kPad + inset,
            width: _kRingSize,
            height: _kRingSize,
            child: IgnorePointer(child: ring(position.round())),
          );
        }
        return RingBarPosition(
          position: position,
          child: Stack(
            children: [
              Positioned.fill(child: barBackground()),
              ?ringLayer,
              ?chips,
            ],
          ),
        );
      },
    );
  }
}

/// 劇画の囲みの丸の代わりの、選ばれた箱。[seed]で、枠の太さを僅かに変える（箱ごとの手作り感）。
class _GekigaRingPainter extends CustomPainter {
  const _GekigaRingPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    MonochromeBoxPainter(
      vertices: [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ],
      thicknessBase: size.width,
      fillColor: GekigaColors.onPanel,
      seed: seed,
      invert: true,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GekigaRingPainter old) => old.seed != seed;
}
