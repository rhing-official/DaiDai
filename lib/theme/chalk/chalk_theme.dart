import 'package:flutter/material.dart';

import '../../models/dark_variant.dart';
import '../app_theme.dart';
import 'chalk_paint.dart';

/// 「チョーク」スタイルの固定パレット（2026-11-26）。黒板の緑に、白いチョークの線。選択中の
/// 印だけ、アクセントカラー（黄色のチョーク）にする。ライト/ダークによらず固定。
class ChalkColors {
  ChalkColors._();

  /// 黒板。
  static const board = Color(0xFF2B3A33);

  /// 黒板より少し明るい面（ダイアログ・カード）。
  static const surface = Color(0xFF33443B);

  /// 白いチョーク。
  static const chalk = Color(0xFFF1EFE3);

  /// チョークの線の色（面の縁）。
  static const line = Color(0x66F1EFE3);
}

/// 現在のテーマがチョークか（箱の装飾の出し分け用）。
class ChalkThemeMarker extends ThemeExtension<ChalkThemeMarker> {
  const ChalkThemeMarker(this.ink);

  /// 線・文字の色（黒板ならチョーク、明るい背景なら濃いペン）。
  final Color ink;

  @override
  ChalkThemeMarker copyWith({Color? ink}) => ChalkThemeMarker(ink ?? this.ink);

  @override
  ChalkThemeMarker lerp(ThemeExtension<ChalkThemeMarker>? other, double t) =>
      this;
}

bool isChalkTheme(BuildContext context) =>
    Theme.of(context).extension<ChalkThemeMarker>() != null;

/// チョークスタイルのThemeData。ライト/ダークの両方へ同じものを渡す。
class ChalkTheme {
  ChalkTheme._();

  /// 暗い背景に引くチョークの色。明るい背景では、代わりに濃い色のペンにする。
  static Color inkFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? ChalkColors.chalk
      : const Color(0xFF2B2B2B);

  /// [background]を渡すと、黒板の代わりに、その色の背景で描く（設定>外観の背景）。
  static ThemeData build(
    Color accentColor,
    String? fontFamily, {
    Color? background,
    Color? textColor,
    Color? onAccentColor,
  }) {
    final palette = background == null
        ? const AppearancePalette(
            background: ChalkColors.board,
            surface: ChalkColors.surface,
            glassBackground: ChalkColors.board,
            glassSurface: ChalkColors.surface,
            outline: ChalkColors.line,
          )
        : AppearancePalette.fromBackground(background);
    final ink = inkFor(palette.background);
    final isDark = ink == ChalkColors.chalk;
    // 設定のフォントカラー（適用済みのものだけ）。線はチョークの色のまま、文字だけを変える。
    final textInk = textColor ?? ink;
    final base = isDark
        ? AppTheme.dark(
            accentColor,
            textColor: textInk,
            onAccentColor: onAccentColor,
            fontFamily: fontFamily,
            palette: palette,
          )
        : AppTheme.light(
            accentColor,
            textColor: textInk,
            onAccentColor: onAccentColor,
            fontFamily: fontFamily,
            palette: palette,
          );
    // 面の縁は、全てチョークで引いた線にする。影は使わない。
    ChalkShapeBorder shape([double radius = 14, double width = 1.8]) =>
        ChalkShapeBorder(
          borderRadius: BorderRadius.circular(radius),
          width: width,
          color: ink,
        );
    ChalkInputBorder field(Color color, double width) =>
        ChalkInputBorder(color: color, width: width);
    return base.copyWith(
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: shape(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: shape(16, 2),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: shape(12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
        side: BorderSide.none,
        shape: shape(12, 1.6),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide.none,
          shape: shape(14, 1.8),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: false,
        border: field(ink, 1.4),
        enabledBorder: field(ink, 1.4),
        disabledBorder: field(ink.withValues(alpha: 0.25), 1.4),
        focusedBorder: field(accentColor.withValues(alpha: 0.95), 2),
        errorBorder: field(base.colorScheme.error, 1.8),
        focusedErrorBorder: field(base.colorScheme.error, 2.2),
      ),
      extensions: [...base.extensions.values, ChalkThemeMarker(ink)],
      dividerTheme: DividerThemeData(
        color: ink.withValues(alpha: 0.28),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
