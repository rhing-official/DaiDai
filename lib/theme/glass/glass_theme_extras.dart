import 'package:flutter/material.dart';

/// ガラスUI用のThemeDataだけでは表現しきれない意匠トークン。
/// [GlassSurface]（`lib/widgets/glass/glass_surface.dart`）が
/// `Theme.of(context).extension<GlassThemeExtras>()`経由で参照する。
@immutable
class GlassThemeExtras extends ThemeExtension<GlassThemeExtras> {
  const GlassThemeExtras({
    required this.chromeBlurSigma,
    required this.floatingBlurSigma,
    required this.chromeTintAlpha,
    required this.floatingTintAlpha,
    required this.cardTintAlpha,
    required this.edgeBorderBaseAlpha,
    required this.edgeBorderHighlightAlpha,
  });

  /// 常設の浮遊要素（ナビチップ・AppBar）のぼかし強度。
  final double chromeBlurSigma;

  /// ダイアログ・ボトムシートのぼかし強度。
  final double floatingBlurSigma;

  /// chromeバリアントの塗りの不透明度。
  final double chromeTintAlpha;

  /// floatingバリアントの塗りの不透明度。
  final double floatingTintAlpha;

  /// cardバリアント（ぼかし無し）の塗りの不透明度。ぼかしで得られる
  /// 「素材感」が無い分、他バリアントより高めにして質感を補う。
  final double cardTintAlpha;

  /// 縁全体に乗せる、均一な薄いアクセントカラーの不透明度。
  final double edgeBorderBaseAlpha;

  /// 縁の左上寄りに乗せる、ハイライト部分の不透明度。
  final double edgeBorderHighlightAlpha;

  @override
  GlassThemeExtras copyWith({
    double? chromeBlurSigma,
    double? floatingBlurSigma,
    double? chromeTintAlpha,
    double? floatingTintAlpha,
    double? cardTintAlpha,
    double? edgeBorderBaseAlpha,
    double? edgeBorderHighlightAlpha,
  }) {
    return GlassThemeExtras(
      chromeBlurSigma: chromeBlurSigma ?? this.chromeBlurSigma,
      floatingBlurSigma: floatingBlurSigma ?? this.floatingBlurSigma,
      chromeTintAlpha: chromeTintAlpha ?? this.chromeTintAlpha,
      floatingTintAlpha: floatingTintAlpha ?? this.floatingTintAlpha,
      cardTintAlpha: cardTintAlpha ?? this.cardTintAlpha,
      edgeBorderBaseAlpha: edgeBorderBaseAlpha ?? this.edgeBorderBaseAlpha,
      edgeBorderHighlightAlpha:
          edgeBorderHighlightAlpha ?? this.edgeBorderHighlightAlpha,
    );
  }

  @override
  GlassThemeExtras lerp(ThemeExtension<GlassThemeExtras>? other, double t) {
    if (other is! GlassThemeExtras) return this;
    return t < 0.5 ? this : other;
  }
}
