import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// `showModalBottomSheet`をガラスUIで包むヘルパー。
/// 背景は透明にし、中身を[GlassSurface]（floatingバリアント、上端のみ角丸）で包む。
Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => GlassSurface(
      variant: GlassVariant.floating,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: builder(context),
    ),
  );
}
