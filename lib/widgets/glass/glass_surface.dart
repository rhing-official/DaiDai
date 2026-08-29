import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/accent_color_provider.dart';
import '../../theme/glass/glass_theme_extras.dart';

/// ガラスマテリアルの用途別バリアント。用途によって`BackdropFilter`を
/// 使うかどうかを切り替える（性能上の理由、[GlassSurface]のコメント参照）。
enum GlassVariant {
  /// 常設の浮遊要素（ナビチップ・AppBarなど）。実際にぼかす。
  chrome,

  /// ダイアログ・ボトムシートなど、同時に1つだけ表示される浮遊要素。実際にぼかす。
  floating,

  /// チャット吹き出し・設定項目・カードなど、画面に多数並びうる面。ぼかさない。
  card,
}

/// Apple Liquid Glassのような「すりガラス越しに背景が透ける」マテリアル。
/// アクセントカラーは背景の塗りには使わず、縁のうっすらとした光彩
/// （リムライト）としてのみ表現する。
///
/// [GlassVariant.chrome]/[.floating]は`BackdropFilter`で実際に背景をぼかす。
/// [GlassVariant.card]は`BackdropFilter`を使わない。1回ごとにフルの
/// save-layer+ぼかし処理が走るため、チャット吹き出しや設定項目のように
/// 画面に多数並ぶ面で毎回ぼかすと重くなる上、背景がほぼ単色の場面では
/// ぼかしても見た目に意味が無いため。
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    this.variant = GlassVariant.card,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.accentColorOverride,
    this.enableEdgeStroke = true,
    this.opaque = false,
    super.key,
  });

  final Widget child;
  final GlassVariant variant;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// 呼び出し側で明示的に色を指定したい場合（例: 選択中の状態を強調したい
  /// ナビチップ）に上書きする。未指定なら[accentColorProvider]の値を使う。
  final Color? accentColorOverride;

  /// 縁の光彩ストローク（[_GlassEdgePainter]）を出すか。角丸の浮遊カード・
  /// タイル・ダイアログでは意匠の一部だが、`borderRadius: BorderRadius.zero`
  /// で使う全面パネル（入力欄コンテナ・タブバー等）では角の丸みで途切れず、
  /// 直線がそのまま「不要な線」に見えてしまうため個別に無効化できるように
  /// している（2026-08-29追加）。
  final bool enableEdgeStroke;

  /// 寄合名・通話ボタン・ハンバーガーメニューのように、下からメッセージが
  /// スクロールしてきても文字が透けて視認性を落とさないようにしたい面向け。
  /// `true`の場合、バリアント別の`tintAlpha`ではなく高い固定の不透明度を
  /// 使う（ぼかし自体は変えない、2026-08-29追加）。
  final bool opaque;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color accent = accentColorOverride ?? ref.watch(accentColorProvider);
    final extras =
        Theme.of(context).extension<GlassThemeExtras>() ?? _fallbackExtras;
    final colorScheme = Theme.of(context).colorScheme;

    final blurSigma = switch (variant) {
      GlassVariant.chrome => extras.chromeBlurSigma,
      GlassVariant.floating => extras.floatingBlurSigma,
      GlassVariant.card => 0.0,
    };
    final tintAlpha = opaque
        ? 0.94
        : switch (variant) {
            GlassVariant.chrome => extras.chromeTintAlpha,
            GlassVariant.floating => extras.floatingTintAlpha,
            GlassVariant.card => extras.cardTintAlpha,
          };

    final fillColor = colorScheme.surface.withValues(alpha: tintAlpha);

    Widget content = ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          if (blurSigma > 0)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(color: fillColor)),
          ),
          if (enableEdgeStroke)
            Positioned.fill(
              child: CustomPaint(
                painter: _GlassEdgePainter(
                  accentColor: accent,
                  borderRadius: borderRadius,
                  baseAlpha: extras.edgeBorderBaseAlpha,
                  highlightAlpha: extras.edgeBorderHighlightAlpha,
                ),
              ),
            ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );

    return content;
  }

  static const GlassThemeExtras _fallbackExtras = GlassThemeExtras(
    chromeBlurSigma: 20,
    floatingBlurSigma: 24,
    chromeTintAlpha: 0.55,
    floatingTintAlpha: 0.6,
    cardTintAlpha: 0.72,
    edgeBorderBaseAlpha: 0.28,
    edgeBorderHighlightAlpha: 0.65,
  );
}

/// マテリアルの縁に、アクセントカラーの薄いグラデーションストロークを描く。
/// 左上寄りをやや強く（ハイライト）、それ以外は均一に薄く乗せることで
/// 「光を受けているガラスの縁」のような見た目にする。
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({
    required this.accentColor,
    required this.borderRadius,
    required this.baseAlpha,
    required this.highlightAlpha,
  });

  final Color accentColor;
  final BorderRadius borderRadius;
  final double baseAlpha;
  final double highlightAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    const strokeWidth = 1.4;
    final inset = rrect.deflate(strokeWidth / 2);

    final gradient = SweepGradient(
      center: Alignment.topLeft,
      colors: [
        accentColor.withValues(alpha: highlightAlpha),
        accentColor.withValues(alpha: baseAlpha),
        accentColor.withValues(alpha: baseAlpha),
        accentColor.withValues(alpha: highlightAlpha * 0.7),
        accentColor.withValues(alpha: highlightAlpha),
      ],
      stops: const [0.0, 0.25, 0.6, 0.85, 1.0],
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);

    canvas.drawRRect(inset, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.baseAlpha != baseAlpha ||
        oldDelegate.highlightAlpha != highlightAlpha;
  }
}
