import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/glass/glass_icon_badge.dart';
import '../../widgets/glass/glass_surface.dart';

/// 語らい一覧・寄合一覧の見出し（トグル・ボタン・会話名の箱）の高さの基準
/// （2026-11-09）。「一対／広場」トグル（`CategoryTab`）の高さ＝上下の余白6＋6
/// と、1行ぶんの文字の高さ（劇画は16、他は13）に等しい。見出しの全部品はこの
/// 高さに揃える。文字の高さは実際のフォント・文字サイズから測る。
double talksControlHeight(BuildContext context, AppUiStyle style) {
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  final painter = TextPainter(
    text: TextSpan(
      // 日本語の文字の高さで測る（画面の文言ではない為、文字コードで書く）。
      text: String.fromCharCode(0x4E00),
      style: base.copyWith(fontSize: style == AppUiStyle.gekiga ? 16 : 13),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.height + 12;
}

/// 丸いアイコンボタン（フラット）。アイコンレール・見出しの＋などで使う。
Widget flatCircleIconButton(
  BuildContext context, {
  required IconData icon,
  required double size,
  required VoidCallback onPressed,
}) {
  final scheme = Theme.of(context).colorScheme;
  return SizedBox(
    width: size,
    height: size,
    child: Material(
      color: scheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkResponse(
        onTap: onPressed,
        child: Center(
          child: Icon(icon, size: size * 0.6, color: scheme.onSurface),
        ),
      ),
    ),
  );
}

/// 版画の見出しのアイコンボタン。`blockIconButton`は影の分の余白（右・下3）を
/// 配置に含めるが、トグル（`CategoryTab`）は含めない為、ここでは含めず、トグルと
/// 同じ高さ・位置になるようにする（影は枠の外へ描かれる）。
Widget blockHeaderButton(
  BuildContext context, {
  required IconData icon,
  required double size,
  VoidCallback? onPressed,
}) {
  final scheme = Theme.of(context).colorScheme;
  final light = Theme.of(context).brightness == Brightness.light;
  return blockMaterialBox(
    context,
    color: light ? Colors.white : scheme.surface,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.55, color: scheme.onSurface),
      ),
    ),
  );
}

/// 見出しのアイコンボタン。高さはトグルと同じ[talksControlHeight]。劇画は枠の太さも
/// トグルと同じ（[kGekigaBoxThicknessBase]）。
class TalksControlButton extends ConsumerWidget {
  const TalksControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final size = talksControlHeight(context, style);
    return switch (style) {
      AppUiStyle.gekiga => GekigaIconButton(
        icon: icon,
        size: size,
        thicknessBase: kGekigaBoxThicknessBase,
        seed: gekigaToolbarIconSeed,
        onPressed: onPressed,
      ),
      AppUiStyle.glass => GlassIconButton(
        icon: icon,
        size: size,
        // アクセントを抜き、縁の光彩を中立色にする。
        accentColorOverride: Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: onPressed,
      ),
      AppUiStyle.block => blockHeaderButton(
        context,
        icon: icon,
        size: size,
        onPressed: onPressed,
      ),
      AppUiStyle.flat => flatCircleIconButton(
        context,
        icon: icon,
        size: size,
        onPressed: onPressed,
      ),
    };
  }
}

/// 寄合一覧の見出しの会話名の箱。トグル（`CategoryTab`）と同じ余白・文字の大きさ・
/// 角の丸み・高さ。トグルの非選択の見た目で、文字だけ太字にする。
class TalksNameChip extends ConsumerWidget {
  const TalksNameChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    Text text(double fontSize, Color? color) => Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: fontSize,
        color: color,
      ),
    );
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
    switch (style) {
      case AppUiStyle.gekiga:
        // トグル（`CategoryTab`の劇画）と同じ構成（横14・縦6・文字16）。
        return GekigaJointedTileList(
          seeds: [label.hashCode],
          selectedFlags: const [false],
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: text(16, GekigaColors.onPanel),
            ),
          ],
        );
      case AppUiStyle.block:
        return blockMaterialBox(
          context,
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : scheme.surface,
          child: Padding(padding: padding, child: text(13, scheme.onSurface)),
        );
      case AppUiStyle.glass:
        return GlassSurface(
          variant: GlassVariant.card,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: padding,
            child: text(13, scheme.onSurfaceVariant),
          ),
        );
      case AppUiStyle.flat:
        return Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: padding,
            child: text(13, scheme.onSurfaceVariant),
          ),
        );
    }
  }
}
