import 'package:flutter/material.dart';

/// ThemeDataだけでは表現しきれない、UIスタイルごとの意匠差分をまとめる拡張。
/// 「浮いている」影の強さなど、ウィジェット側から`Theme.of(context)`経由で参照する。
@immutable
class AppThemeExtras extends ThemeExtension<AppThemeExtras> {
  const AppThemeExtras({required this.floatingShadow});

  /// ボタン・カード・チャット吹き出しなど、通常のMaterial elevationが
  /// 効かないカスタム描画に適用する「浮いている」影。
  final List<BoxShadow> floatingShadow;

  static const none = <BoxShadow>[];

  @override
  AppThemeExtras copyWith({List<BoxShadow>? floatingShadow}) {
    return AppThemeExtras(
      floatingShadow: floatingShadow ?? this.floatingShadow,
    );
  }

  @override
  AppThemeExtras lerp(ThemeExtension<AppThemeExtras>? other, double t) {
    if (other is! AppThemeExtras) return this;
    return t < 0.5 ? this : other;
  }
}
