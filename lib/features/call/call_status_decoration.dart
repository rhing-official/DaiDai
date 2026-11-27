import 'package:flutter/material.dart';

import '../../theme/chalk/chalk_paint.dart';
import '../../theme/chalk/chalk_theme.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通話画面の上に重ねる小さな案内（接続中、接続の不安定など）の枠（2026-11-27）。映像の上に載るので、
/// 塗りは半透明の黒のまま、線だけスタイルに合わせる。フラットはアクセントカラーの線、チョークは
/// チョークの線。それ以外のスタイルは、従来どおり線なし。
Decoration callStatusDecoration(
  BuildContext context,
  WidgetRef ref, {
  required double radius,
}) {
  final scheme = Theme.of(context).colorScheme;
  final borderRadius = BorderRadius.circular(radius);
  if (isChalkTheme(context)) {
    return ChalkBoxDecoration(
      color: Colors.black54,
      borderRadius: borderRadius,
      lineColor: scheme.onSurface,
    );
  }
  final flat = ref.watch(appUiStyleProvider) == AppUiStyle.flat;
  return BoxDecoration(
    color: Colors.black54,
    borderRadius: borderRadius,
    border: flat ? Border.all(color: scheme.primary) : null,
  );
}
