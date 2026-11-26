import 'package:flutter/material.dart';

import '../../models/dark_variant.dart';
import '../app_theme.dart';

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

/// チョークスタイルのThemeData。ライト/ダークの両方へ同じものを渡す。
class ChalkTheme {
  ChalkTheme._();

  static ThemeData build(Color accentColor, String? fontFamily) =>
      AppTheme.dark(
        accentColor,
        textColor: ChalkColors.chalk,
        fontFamily: fontFamily,
        palette: const AppearancePalette(
          background: ChalkColors.board,
          surface: ChalkColors.surface,
          glassBackground: ChalkColors.board,
          glassSurface: ChalkColors.surface,
          outline: ChalkColors.line,
        ),
      );
}
