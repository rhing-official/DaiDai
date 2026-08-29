import 'package:flutter/material.dart';

import 'glass_colors.dart';
import 'glass_theme_extras.dart';
import '../app_theme.dart';

/// ガラスUI用のThemeDataを組み立てる。[AppTheme]と同じくアクセントカラーを
/// seedにしてColorSchemeを導出するが、cardTheme/appBarTheme/dialogThemeは
/// 完全に透明にする。実際の「すりガラス」の見た目（ぼかし・半透明の塗り・
/// 縁の光彩）はThemeDataではなく`lib/widgets/glass/`のウィジェット
/// （[GlassSurface]等）が描画するため、ThemeData側は極力何も描かず
/// 邪魔をしないことに徹する。
class GlassTheme {
  GlassTheme._();

  static ThemeData light(Color accentColor) =>
      _build(accentColor, Brightness.light);

  static ThemeData dark(Color accentColor) =>
      _build(accentColor, Brightness.dark);

  static ThemeData _build(Color accentColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // アクセントカラーが白に近い明るい色だと、決め打ちの白文字では
    // ボタン等が読めなくなる。アクセントカラー自体の明度から動的に
    // 計算するのではなく、ライトモードは黒・ダークモードは白という
    // 固定ルールに統一する（2026-08-29追加）。
    final onAccent = isDark ? Colors.white : Colors.black;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ).copyWith(primary: accentColor, onPrimary: onAccent);
    // onSurface/onSurfaceVariant（文字・アイコン色）は、fromSeed任せだと
    // アクセントカラーの色相が乗って視認性が落ちるため、ライト/ダーク各1色の
    // 固定色に上書きする（2026-08-29追記、GlassColors.lightForeground/
    // darkForeground参照）。
    if (isDark) {
      colorScheme = colorScheme.copyWith(
        surface: GlassColors.darkBackground,
        surfaceContainerHighest: GlassColors.darkSurfaceBase,
        onSurface: GlassColors.darkForeground,
        onSurfaceVariant: GlassColors.darkForeground,
      );
    } else {
      colorScheme = colorScheme.copyWith(
        surface: GlassColors.lightBackground,
        surfaceContainerHighest: GlassColors.lightSurfaceBase,
        onSurface: GlassColors.lightForeground,
        onSurfaceVariant: GlassColors.lightForeground,
      );
    }
    final backgroundColor = isDark
        ? GlassColors.darkBackground
        : GlassColors.lightBackground;

    final extras = GlassThemeExtras(
      chromeBlurSigma: 20,
      floatingBlurSigma: 24,
      chromeTintAlpha: isDark ? 0.45 : 0.55,
      floatingTintAlpha: isDark ? 0.5 : 0.6,
      cardTintAlpha: isDark ? 0.6 : 0.72,
      edgeBorderBaseAlpha: isDark ? 0.32 : 0.28,
      edgeBorderHighlightAlpha: isDark ? 0.75 : 0.65,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.comfortable,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PopSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: PopSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: PopSlidePageTransitionsBuilder(),
          TargetPlatform.windows: PopSlidePageTransitionsBuilder(),
          TargetPlatform.linux: PopSlidePageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: null,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: onAccent,
              elevation: 6,
              shadowColor: accentColor.withValues(alpha: 0.5),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                Colors.white.withValues(alpha: 0.12),
              ),
            ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: onAccent,
        elevation: 6,
        highlightElevation: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            (isDark
                    ? GlassColors.darkSurfaceBase
                    : GlassColors.lightSurfaceBase)
                .withValues(alpha: extras.cardTintAlpha),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: accentColor.withValues(alpha: extras.edgeBorderBaseAlpha),
          ),
        ),
      ),
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme
          .apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
      extensions: [extras],
    );
  }
}
