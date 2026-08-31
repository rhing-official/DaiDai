import 'package:flutter/material.dart';

import '../models/app_ui_style.dart';
import 'gekiga/gekiga_colors.dart';
import 'glass/glass_colors.dart';

/// ボタン直下に`showMenu`で出す独自デザインのポップアップ（ピン留め
/// メッセージ・アルバム・ハンバーガーメニュー等）共通の背景・文字色・枠線。
/// `colorScheme.inverseSurface`/`onInverseSurface`はアクセントカラーを
/// seedにした`ColorScheme.fromSeed`から導出されるため、アクセントカラー
/// 次第で視認性が落ちるため、アクセントカラーに一切依存しない固定色にする。
/// フラット/ガラスは同じ固定トーン（2026-08-31、両スタイルとも画面背景と
/// ほぼ同色になり視認性が低かったため、画面背景よりはっきり区別できる
/// 中立グレー＋枠線に変更。ガラスもこの不透明な固定色に統一し、
/// `GlassSurface`の半透明パネルは使わない）。劇画は独自の固定パレット
/// （`GekigaColors.panel`/`onPanel`、黒背景＋白文字）を使う（2026-08-31、
/// 劇画もフラット用の中立グレーがそのまま使われ世界観から浮いていたため
/// 個別対応）。
/// （2026-08-30、`chat_screen.dart`の`_popupCardBackground`/
/// `_popupCardForeground`・`album_popup_content.dart`の同名関数として
/// 個別に重複実装されていたのを共通化、2026-08-31）。
Color popupCardBackground(Brightness brightness, AppUiStyle uiStyle) {
  if (uiStyle == AppUiStyle.gekiga) return GekigaColors.panel;
  return brightness == Brightness.dark
      ? const Color(0xFF2C2C34)
      : const Color(0xFFE7E7EC);
}

Color popupCardForeground(Brightness brightness, AppUiStyle uiStyle) {
  if (uiStyle == AppUiStyle.gekiga) return GekigaColors.onPanel;
  return brightness == Brightness.dark
      ? GlassColors.darkForeground
      : GlassColors.lightForeground;
}

Color popupCardBorder(Brightness brightness, AppUiStyle uiStyle) {
  if (uiStyle == AppUiStyle.gekiga) return GekigaColors.onPanel;
  return brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.black.withValues(alpha: 0.14);
}
