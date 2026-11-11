import 'package:flutter/material.dart';

/// 透過PNGのアイコンの透過部分に敷く色（2026-11-11）。アクセントカラーではなく、
/// 外観（ライト／ダーク）の色にする。ライトは白、ダークは各スタイルが中立色に固定した
/// `colorScheme.surface`。フラット・ガラス・版画で使う（劇画は自前の枠を使う）。
Color avatarBackdropColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surface
      : Colors.white;
}
