import 'package:flutter/material.dart';

/// ThemeDataだけでは表現しきれない、UIスタイルごとの意匠差分をまとめる拡張。
/// 「浮いている」影の強さなど、ウィジェット側から`Theme.of(context)`経由で参照する。
@immutable
class AppThemeExtras extends ThemeExtension<AppThemeExtras> {
  const AppThemeExtras({
    required this.floatingShadow,
    required this.textTertiary,
  });

  /// ボタン・カード・チャット吹き出しなど、通常のMaterial elevationが
  /// 効かないカスタム描画に適用する「浮いている」影。
  final List<BoxShadow> floatingShadow;

  /// テキスト・アイコンの重要度階調（`text_prominence_colors.dart`参照）の
  /// Tier3（補助・タイムスタンプ・ヒント・無効化アイコン）用固定色。
  final Color textTertiary;

  static const none = <BoxShadow>[];

  @override
  AppThemeExtras copyWith({
    List<BoxShadow>? floatingShadow,
    Color? textTertiary,
  }) {
    return AppThemeExtras(
      floatingShadow: floatingShadow ?? this.floatingShadow,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  AppThemeExtras lerp(ThemeExtension<AppThemeExtras>? other, double t) {
    if (other is! AppThemeExtras) return this;
    return t < 0.5 ? this : other;
  }
}
