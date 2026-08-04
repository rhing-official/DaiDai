import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../app_theme_extras.dart';
import 'gekiga_colors.dart';

/// 劇画UIスタイル用のThemeData。simpleスタイル（[AppTheme]）と異なり、
/// アクセントカラーは一切使わず、背景（赤）以外は全て黒・白のモノクロで
/// 統一する（2026-08-04変更。以前はFABなど一部にアクセントカラーを残す
/// 方針だったが、ユーザー指摘により完全無効化した）。
/// themeMode（ライト/ダーク）に関わらず常に同じ見た目にするため、
/// light/darkの2関数を分けず単一のThemeDataを返す（2026-07-30新規）。
class GekigaTheme {
  GekigaTheme._();

  static ThemeData build() {
    // `ColorScheme.dark()`をそのまま土台にすると、ここで明示的に
    // 上書きしていないトークン（primaryContainer・tertiary・
    // surfaceContainerHighest・outline等）にMaterial既定のダークテーマ色
    // （紫系）が残ってしまい、「背景以外は全てモノクロに」という要件を
    // 満たせない（リアクションチップの塗り色等で実際に漏れていた）。
    // 彩度ゼロのグレーをseedにした`ColorScheme.fromSeed`を土台にすることで、
    // 明示的に上書きしないトークンも含めて無彩色のグレー階調に揃える。
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.dark,
        ).copyWith(
          surface: GekigaColors.background,
          onSurface: GekigaColors.onPanel,
          primary: GekigaColors.onPanel,
          onPrimary: GekigaColors.panel,
          secondary: GekigaColors.panel,
          onSecondary: GekigaColors.onPanel,
          // `onSurfaceVariant`/`outline`/`outlineVariant`はfromSeedの既定だと
          // 中間グレーになり、説明文・仕切り線が灰色に見えてしまっていた
          // （2026-08-04発覚・修正）。他の劇画UI要素と同じ白系に統一する。
          onSurfaceVariant: GekigaColors.onPanel,
          outline: GekigaColors.onPanel,
          outlineVariant: GekigaColors.onPanel.withValues(alpha: 0.24),
        );

    // 本文はCJK文字幅の推定崩れ（app_theme.dartのコメント参照）を避ける
    // ため既定のシステムフォントのままにし、太字ラテン体フォント（Anton、
    // 日本語グリフ非対応）はdisplayLarge/Medium/Smallという、このアプリ
    // では現状ほぼ使われていない「英数字主体の大きな見出し・ロゴ・
    // カウンター表示」向けの置き場所だけに限定して当てる。AppBarタイトルや
    // 設定の見出しラベルなど日本語が主体のテキストには適用しない
    // （当てても結局グリフが無くシステムフォントへフォールバックする
    // だけで、太字＋字間調整の方が素直に劇画らしさを出せるため）。
    final baseText = ThemeData.dark().textTheme.apply(
      bodyColor: GekigaColors.onPanel,
      displayColor: GekigaColors.onPanel,
    );
    final displayStyle = GoogleFonts.anton();
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.merge(displayStyle),
      displayMedium: baseText.displayMedium?.merge(displayStyle),
      displaySmall: baseText.displaySmall?.merge(displayStyle),
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
        titleTextStyle: baseText.titleLarge?.copyWith(
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
          textStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      // Material3既定のFilledButton/OutlinedButtonは角丸＋ColorScheme由来の
      // 色が残るため、elevatedButtonThemeと同じ黒地白文字・角丸なしに揃える
      // （2026-08-04追加。ダイアログの保存/削除ボタン等がここに未対応だと
      // モノクロ化が徹底されない）。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GekigaColors.panel,
          foregroundColor: GekigaColors.onPanel,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GekigaColors.onPanel,
          side: BorderSide(color: GekigaColors.onPanel),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: GekigaColors.panel,
        foregroundColor: GekigaColors.onPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
