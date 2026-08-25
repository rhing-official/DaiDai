import 'package:flutter/material.dart';

import '../app_theme_extras.dart';
import 'dessin_colors.dart';

/// デッサンUIスタイル用のThemeData。劇画UI（[GekigaTheme]）と同様、
/// themeMode（ライト/ダーク）に関わらず常に同じ見た目にするため、
/// light/darkの2関数を分けず単一のThemeDataを返す。ユーザーによる背景色
/// カスタムは今回スコープ外（劇画UIも導入当初は固定色のみだった、
/// 2026-08-05に`gekigaBackgroundColorProvider`が追加された段階的な経緯と
/// 同じ方針）。
class DessinTheme {
  DessinTheme._();

  static ThemeData build() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
        ).copyWith(
          surface: DessinColors.paper,
          onSurface: DessinColors.ink,
          primary: DessinColors.ink,
          onPrimary: DessinColors.paper,
          secondary: DessinColors.graphite,
          onSecondary: DessinColors.paper,
          onSurfaceVariant: DessinColors.graphite,
          outline: DessinColors.graphite,
          outlineVariant: DessinColors.graphiteLight,
        );

    final baseText = ThemeData.light().textTheme.apply(
      bodyColor: DessinColors.ink,
      displayColor: DessinColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DessinColors.paper,
      colorScheme: colorScheme,
      textTheme: baseText,
      // 鉛筆のざらついた質感の意匠に、Material標準の丸い波紋は馴染まない
      // ため無効化する（劇画UIと同じ方針）。
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: DessinColors.paper,
        foregroundColor: DessinColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: DessinColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: DessinColors.graphiteLight),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DessinColors.ink,
          foregroundColor: DessinColors.paper,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DessinColors.ink,
          foregroundColor: DessinColors.paper,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DessinColors.ink,
          side: const BorderSide(color: DessinColors.ink),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: DessinColors.paperShade,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide.none,
        ),
      ),
      dividerColor: DessinColors.graphiteLight,
      extensions: const [AppThemeExtras(floatingShadow: AppThemeExtras.none)],
    );
  }
}
