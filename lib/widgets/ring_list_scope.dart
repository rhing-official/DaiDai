import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/chalk/chalk_paint.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'glass/glass_surface.dart';
import 'washi_nav_bar.dart';

/// 「丸で囲む」の時の項目の並び（2026-11-26）。項目の箱を1つの大きなブロックにまとめ、選択中の
/// 項目を線の枠（角丸）で囲む。この範囲の中の項目は、自分の箱・塗りを描かない（枠と塗りは、
/// 並びが描く）。中のウィジェットからは、[RingListScope.styleOf]で、外側のUIスタイルが分かる。
class RingListScope extends InheritedWidget {
  const RingListScope({required this.style, required super.child, super.key});

  /// 外側の（本当の）UIスタイル。中は、項目が自前の箱を描かないよう、フラット扱いにしてある。
  final AppUiStyle style;

  /// この範囲の中なら、外側のUIスタイル。範囲の外ならnull。
  static AppUiStyle? styleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RingListScope>()?.style;

  @override
  bool updateShouldNotify(RingListScope old) => old.style != style;
}

class _FlatStyleNotifier extends AppUiStyleNotifier {
  @override
  AppUiStyle build() => AppUiStyle.flat;
}

/// 「丸で囲む」の時だけ、[child]（項目の並び）を、1つの大きなブロックの中に置き、中の項目から、
/// 箱・選択の塗りを取り除く。それ以外の時、劇画（並び全体を既に1つの箱で描く）は、[child]をそのまま返す。
///
/// 項目は、UIスタイルをフラットとして描くようにしてある（枠付きの箱・ガラス・選択の塗りは
/// 出ない）。選択中の枠は、並びの種類ごとに、[RingOutline]で重ねる。
class RingListBlock extends ConsumerWidget {
  const RingListBlock({
    required this.child,
    this.withBackground = true,
    super.key,
  });

  final Widget child;

  /// 大きなブロックの背景を、ここで描くか。`false`なら、呼び出し側が描く（枠だけ重ねる）。
  final bool withBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    if (!ref.watch(navBandMergedProvider) || style == AppUiStyle.gekiga) {
      return child;
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 項目の塗り（面の色）は透明にする。枠付きの箱の判定（拡張）も外す。
    final plain = theme.copyWith(
      colorScheme: scheme.copyWith(
        surface: Colors.transparent,
        // 版画・チョークの項目は、文字を、設定のフォントカラー（onSurface）で描く。フラット扱いに
        // すると、控えめな色（onSurfaceVariant）になり、設定と違って見えるので、そろえる。
        onSurfaceVariant: style == AppUiStyle.block || style == AppUiStyle.chalk
            ? scheme.onSurface
            : null,
      ),
      extensions: [
        for (final e in theme.extensions.values)
          if (e is! BlockThemeMarker &&
              !e.runtimeType.toString().contains('Chalk'))
            e,
      ],
    );
    final body = ProviderScope(
      overrides: [appUiStyleProvider.overrideWith(_FlatStyleNotifier.new)],
      child: Theme(
        data: plain,
        child: RingListScope(style: style, child: child),
      ),
    );
    if (!withBackground) return body;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: ringBlockBackground(context, style)),
        body,
      ],
    );
  }
}

/// 大きなブロックの背景（スタイルごと）。劇画は、並びが自分で描くので、ここでは描かない。
Widget ringBlockBackground(BuildContext context, AppUiStyle style) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final brightness = theme.brightness;
  switch (style) {
    case AppUiStyle.glass:
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox.expand(),
      );
    case AppUiStyle.block:
      return DecoratedBox(
        decoration: BoxDecoration(
          color: brightness == Brightness.light ? Colors.white : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: BlockTheme.lineColor(brightness),
            width: BlockTheme.borderWidth,
          ),
          boxShadow: BlockTheme.shadow(scheme.primary, brightness),
        ),
      );
    case AppUiStyle.chalk:
      // メニューチップの帯と同じ: 塗らず、チョークの線の枠だけ。
      return DecoratedBox(
        decoration: ChalkBoxDecoration(
          borderRadius: BorderRadius.circular(16),
          lineColor: scheme.onSurface,
          lineWidth: 2.4,
        ),
      );
    case AppUiStyle.washi:
      // メニューチップの帯と同じ: へこんだ面。
      return CustomPaint(painter: WashiInsetBlockPainter(scheme.surface, 16));
    case AppUiStyle.gekiga:
      return const SizedBox.shrink();
    case AppUiStyle.flat:
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
      );
  }
}

/// 選択中の項目を囲む、線の角丸の枠（塗らない）。アクセントカラーの線（劇画は白）。メニューチップの丸と同じ。
class RingOutline extends StatelessWidget {
  const RingOutline({required this.style, this.radius = 12, super.key});

  final AppUiStyle style;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = BorderRadius.circular(style == AppUiStyle.gekiga ? 3 : radius);
    if (style == AppUiStyle.chalk) {
      return DecoratedBox(
        decoration: ChalkBoxDecoration(
          borderRadius: r,
          lineColor: scheme.primary,
          lineWidth: 2.2,
        ),
      );
    }
    final (Color color, double width) = switch (style) {
      AppUiStyle.glass => (scheme.onSurface.withValues(alpha: 0.7), 1.6),
      AppUiStyle.block => (
        BlockTheme.lineColor(theme.brightness),
        BlockTheme.borderWidth,
      ),
      AppUiStyle.gekiga => (GekigaColors.onPanel, 3),
      AppUiStyle.washi => (scheme.primary, 1.8),
      _ => (scheme.primary, 2),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: color, width: width),
      ),
    );
  }
}
