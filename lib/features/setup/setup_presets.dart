import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/chat_layout_style.dart';
import '../../models/font_design.dart';
import '../../models/talks_list_layout_style.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/chat_layout_style_provider.dart';
import '../../providers/font_design_provider.dart';
import '../../providers/talks_list_layout_style_provider.dart';
import '../../providers/theme_mode_provider.dart';

/// 初期設定の「おすすめ」1件分（2026-10-31追加）。選ぶと、これらをまとめて
/// 設定する。nullの項目は今の値のままにする。
class SetupPreset {
  const SetupPreset({
    required this.uiStyle,
    required this.themeMode,
    required this.accent,
    required this.fontDesign,
    required this.chatLayout,
    required this.talksListLayout,
  });

  final AppUiStyle uiStyle;
  final ThemeMode themeMode;
  final Color? accent;
  final FontDesign fontDesign;
  final ChatLayoutStyle chatLayout;
  final TalksListLayoutStyle talksListLayout;
}

/// 標準・くっきり・遊び心の順。標準は、保存値が無い時の既定値と同じ。
const kSetupPresets = <SetupPreset>[
  SetupPreset(
    uiStyle: AppUiStyle.glass,
    themeMode: ThemeMode.system,
    accent: Color(0xCCA997C6),
    fontDesign: FontDesign.zenMaruGothic,
    chatLayout: ChatLayoutStyle.allLeft,
    talksListLayout: TalksListLayoutStyle.iconSplit,
  ),
  SetupPreset(
    uiStyle: AppUiStyle.flat,
    themeMode: ThemeMode.light,
    accent: Color(0xCC114789),
    fontDesign: FontDesign.notoSansJp,
    chatLayout: ChatLayoutStyle.sideBySide,
    talksListLayout: TalksListLayoutStyle.standard,
  ),
  SetupPreset(
    uiStyle: AppUiStyle.gekiga,
    themeMode: ThemeMode.system,
    accent: null,
    fontDesign: FontDesign.zenMaruGothic,
    chatLayout: ChatLayoutStyle.allLeft,
    talksListLayout: TalksListLayoutStyle.iconSplit,
  ),
];

/// [preset]の内容を、各設定に書く（端末とFirestoreに保存される）。
Future<void> applySetupPreset(WidgetRef ref, SetupPreset preset) async {
  await ref.read(appUiStyleProvider.notifier).setStyle(preset.uiStyle);
  await ref.read(appThemeModeProvider.notifier).setMode(preset.themeMode);
  final accent = preset.accent;
  if (accent != null) {
    await ref.read(accentColorProvider.notifier).setColor(accent);
  }
  await ref.read(fontDesignProvider.notifier).setDesign(preset.fontDesign);
  await ref.read(chatLayoutStyleProvider.notifier).setStyle(preset.chatLayout);
  await ref
      .read(talksListLayoutStyleProvider.notifier)
      .setStyle(preset.talksListLayout);
}
