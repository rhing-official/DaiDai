import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';

/// トグル類（スイッチ・チェックボックス・ラジオ）の色。UIスタイル毎に決める
/// （2026-11-05）。文字にアクセントカラーは使わず、アクセントは塗りにだけ使う。
class ToggleColors {
  const ToggleColors({
    required this.onFill,
    required this.offFill,
    required this.onThumb,
    required this.offThumb,
    required this.border,
    required this.borderWidth,
    required this.check,
  });

  /// オンの時の塗り（トラック・チェックボックスの面）。
  final Color onFill;
  final Color offFill;

  /// つまみ・チェック・ラジオの中の丸の色。
  final Color onThumb;
  final Color offThumb;
  final Color border;
  final double borderWidth;

  /// オンのつまみ・面の上に描くチェックの色。
  final Color check;

  static ToggleColors of(
    BuildContext context,
    WidgetRef ref, {
    bool onDark = false,
  }) {
    final style = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    switch (style) {
      case AppUiStyle.gekiga:
        // 黒いタイル（選択行など）の上では白黒を反転する。
        if (onDark) {
          return const ToggleColors(
            onFill: GekigaColors.onPanel,
            offFill: GekigaColors.panel,
            onThumb: GekigaColors.panel,
            offThumb: GekigaColors.onPanel,
            border: GekigaColors.onPanel,
            borderWidth: 2.5,
            check: GekigaColors.onPanel,
          );
        }
        return const ToggleColors(
          onFill: GekigaColors.panel,
          offFill: GekigaColors.onPanel,
          onThumb: GekigaColors.onPanel,
          offThumb: GekigaColors.panel,
          border: GekigaColors.panel,
          borderWidth: 2.5,
          check: GekigaColors.panel,
        );
      case AppUiStyle.glass:
        return ToggleColors(
          onFill: accent.withValues(alpha: 0.6),
          offFill: scheme.onSurface.withValues(alpha: 0.14),
          onThumb: Colors.white.withValues(alpha: 0.95),
          offThumb: Colors.white.withValues(alpha: 0.8),
          border: scheme.onSurface.withValues(alpha: 0.28),
          borderWidth: 1,
          check: accent,
        );
      case AppUiStyle.block:
        final line = BlockTheme.lineColor(scheme.brightness);
        // オン=アクセントの面（つまみは黒＋白いチェック）、オフ=白い面（つまみは黒）で、
        // 背景の淡い色と見分けがつくようにする。チェックはつまみ（黒/明るい線）の上に
        // 描くので反対色にする。チェックボックスのチェックは`onThumb`（面の上）を使う。
        final isDark = scheme.brightness == Brightness.dark;
        return ToggleColors(
          onFill: accent,
          offFill: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          onThumb: line,
          offThumb: line,
          border: line,
          borderWidth: BlockTheme.borderWidth,
          check: isDark ? const Color(0xFF121212) : Colors.white,
        );
      case AppUiStyle.flat:
        return ToggleColors(
          onFill: accent,
          offFill: scheme.onSurface.withValues(alpha: 0.12),
          onThumb: onAccent,
          offThumb: scheme.onSurface.withValues(alpha: 0.55),
          border: scheme.onSurface.withValues(alpha: 0.35),
          borderWidth: 1.5,
          check: accent,
        );
    }
  }
}

/// 動きの長さはUIスタイルによらず全て同じ（2026-11-05、ユーザー指示）。
Duration toggleDurationFor(WidgetRef ref, Duration spring) => spring;
