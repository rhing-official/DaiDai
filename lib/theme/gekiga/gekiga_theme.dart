import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/font_design.dart';
import '../app_theme.dart';
import '../app_theme_extras.dart';
import 'gekiga_colors.dart';
import 'gekiga_fonts.dart';

/// 劇画UIスタイル用のThemeData。simpleスタイル（[AppTheme]）と異なり、
/// アクセントカラーは背景・パネル等の主要色には使わず、FABなどごく一部の
/// 強調要素だけに残す（身だしなみの「イメージカラー」がチャットのバッジ
/// 塗りに残る既存方針をアプリ全体に拡張したもの）。
/// themeMode（ライト/ダーク）に関わらず常に同じ見た目にするため、
/// light/darkの2関数を分けず単一のThemeDataを返す（2026-07-30新規）。
class GekigaTheme {
  GekigaTheme._();

  static ThemeData build(Color accentColor, FontDesign fontDesign) {
    final colorScheme = const ColorScheme.dark().copyWith(
      surface: GekigaColors.background,
      onSurface: GekigaColors.onPanel,
      primary: accentColor,
      onPrimary: Colors.white,
      secondary: GekigaColors.panel,
      onSecondary: GekigaColors.onPanel,
    );

    // 本文はCJK文字幅の推定崩れ（app_theme.dartのコメント参照）を避ける
    // ため既定のシステムフォントのままにし、太字ラテン体フォント（Anton、
    // 日本語グリフ非対応）はdisplayLarge/Medium/Smallという、このアプリ
    // では現状ほぼ使われていない「英数字主体の大きな見出し・ロゴ・
    // カウンター表示」向けの置き場所だけに限定して当てる（常時適用）。
    final baseText = ThemeData.dark().textTheme.apply(
      bodyColor: GekigaColors.onPanel,
      displayColor: GekigaColors.onPanel,
    );
    final displayStyle = GoogleFonts.anton();
    // フォントデザイン設定で「劇画」を選んだ場合のみ、見出し・メニュー系の
    // TextTheme（タイトル・ボタン文字）にも劇画フォントを当てる
    // （こちらもAnton同様CJKグリフを持たないため、日本語表示時は結局
    // システムフォントへフォールバックするだけになるが、ユーザーが
    // 明示的にオプトインした結果なので許容する。2026-08-03追加）。
    final menuStyle = fontDesign == FontDesign.gekiga
        ? const TextStyle(fontFamily: GekigaFonts.menuFontFamily)
        : null;
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.merge(displayStyle),
      displayMedium: baseText.displayMedium?.merge(displayStyle),
      displaySmall: baseText.displaySmall?.merge(displayStyle),
      titleLarge: baseText.titleLarge?.merge(menuStyle),
      titleMedium: baseText.titleMedium?.merge(menuStyle),
      titleSmall: baseText.titleSmall?.merge(menuStyle),
      labelLarge: baseText.labelLarge?.merge(menuStyle),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: GekigaColors.background,
      colorScheme: colorScheme,
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PopSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: PopSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: PopSlidePageTransitionsBuilder(),
          TargetPlatform.windows: PopSlidePageTransitionsBuilder(),
          TargetPlatform.linux: PopSlidePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: GekigaColors.background,
        foregroundColor: GekigaColors.onPanel,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: const CardThemeData(
        color: GekigaColors.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GekigaColors.panel,
          foregroundColor: GekigaColors.onPanel,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: GekigaColors.panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide.none,
        ),
      ),
      dividerColor: GekigaColors.onPanel.withValues(alpha: 0.24),
      extensions: const [AppThemeExtras(floatingShadow: AppThemeExtras.none)],
    );
  }
}
