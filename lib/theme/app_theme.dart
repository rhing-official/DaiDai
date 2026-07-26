import 'package:flutter/material.dart';

import 'app_theme_extras.dart';

/// シンプルUI用のThemeDataを組み立てる。
/// アクセントカラーはユーザーがカラーコードで指定でき、そこから
/// Material3のカラースキーム全体を導出する。ライト/ダーク共通のロジックは
/// [_build]にまとめ、[light]/[dark]はbrightness違いの薄いラッパーにしている。
///
/// フォントは意図的に指定していない（プラットフォーム既定にフォールバック）。
/// 以前は`fontFamily: 'monospace'`を指定していたが、CJK（日本語）文字の
/// 字幅計算とレイアウトエンジンの推定字幅がズレ、複数文字のラベル
/// （例:「工房」）だけ折り返される不具合の原因になっていた
/// （1文字のラベルは偶然収まっていたため気づきにくかった）。
/// CLAUDE.mdが意図する等幅フォント（BIZ UDPMincho/BIZ UDGothic）は
/// まだフォントアセットが未取得（pubspec.yamlのfonts:も未設定）のため、
/// 実際に導入する際は日本語グリフの字幅もあわせて確認すること。
class AppTheme {
  AppTheme._();

  /// ダークモードの背景・カード色（ユーザー指定のダークグレー）。
  /// `ColorScheme.fromSeed`がダーク用に生成するsurfaceは、アクセントカラーの
  /// 色相を帯びた紺・緑がかったグレーになりやすく、素直な「ダークグレー」に
  /// ならないため、背景・カード面はアクセントカラーに関わらずこの2色に固定する。
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);

  static ThemeData light(Color accentColor) =>
      _build(accentColor, Brightness.light);

  static ThemeData dark(Color accentColor) =>
      _build(accentColor, Brightness.dark);

  static ThemeData _build(Color accentColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ).copyWith(primary: accentColor, onPrimary: Colors.white);
    if (isDark) {
      colorScheme = colorScheme.copyWith(
        surface: darkBackground,
        surfaceContainerHighest: darkSurface,
      );
    }
    final backgroundColor = isDark ? darkBackground : colorScheme.surface;
    final cardColor = isDark ? darkSurface : colorScheme.surfaceContainerHighest;

    final floatingShadow = [
      BoxShadow(
        color: accentColor.withValues(alpha: 0.22),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.comfortable,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _PopSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: _PopSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: _PopSlidePageTransitionsBuilder(),
          TargetPlatform.windows: _PopSlidePageTransitionsBuilder(),
          TargetPlatform.linux: _PopSlidePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 6,
        shadowColor: accentColor.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          elevation: 10,
          shadowColor: accentColor.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          // 押した瞬間はぺたっと沈む＝浮いていた分の影が消えるように見せる。
          elevation: const WidgetStatePropertyAll(10),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 10,
        highlightElevation: 14,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
      extensions: [AppThemeExtras(floatingShadow: floatingShadow)],
    );
  }
}

/// 少し下から浮き上がりながらフェードイン＋わずかに拡大する「ポップ」演出。
class _PopSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _PopSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
