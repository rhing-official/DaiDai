import 'package:flutter/material.dart';

import '../models/dark_variant.dart';

/// テーマが使う色の役割（背景、面、吹き出しなど）を、部品へ渡す（2026-11-27）。
///
/// 背景色から作る色は、[AppearancePalette]の1か所で作る。部品は、背景色から自分で色を混ぜず、
/// ここから役割の色を読む。利用者の背景色も、意匠の背景色も、同じ[AppearancePalette]を通る。
/// 劇画は専用の見た目なので、この拡張を持たない。
@immutable
class AppearanceRoles extends ThemeExtension<AppearanceRoles> {
  const AppearanceRoles(this.palette);

  final AppearancePalette palette;

  /// この`context`のテーマの色の組。無ければ（劇画、テスト）null。
  static AppearancePalette? paletteOf(BuildContext context) =>
      Theme.of(context).extension<AppearanceRoles>()?.palette;

  @override
  AppearanceRoles copyWith({AppearancePalette? palette}) =>
      AppearanceRoles(palette ?? this.palette);

  @override
  AppearanceRoles lerp(ThemeExtension<AppearanceRoles>? other, double t) =>
      other is AppearanceRoles && t >= 0.5 ? other : this;
}
