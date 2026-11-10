import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import 'gekiga/gekiga_icon_badge.dart';
import 'glass/glass_icon_badge.dart';
import 'press_drag_menu.dart';

/// アルバム・ノート（マークダウン・ドロー）のペイン上部で、幅が狭い時に右端のボタン群を
/// ハンバーガーメニュー1つにまとめるための部品（2026-11-10、ユーザー指示）。
///
/// 縦画面の狭いペインでは、題名の入力欄がボタンの幅を引いた残りしか使えず、題名が途中で切れる。
/// 題名の文字サイズは中（アプリの文字サイズ設定・題名欄の指定）で決めているので縮めず、
/// 狭い時だけボタンをハンバーガーに畳んで、題名に全幅を使わせる（行は分けない）。

/// ボタン1つぶんの幅（`IconButton`の既定）。
const double kPaneActionWidth = 48;

/// 題名に最低でも残したい文字数（これだけ入らなければハンバーガーにまとめる）。
const double kPaneTitleMinChars = 9;

/// 題名の左右の余白（`AppBar`の`titleSpacing`と同じ）。
const double kPaneTitleRowPadding = 16;

/// ボタンを題名と同じ行に並べると、題名の幅が足りなくなるか。
///
/// [maxWidth]はペイン自身の幅、[actionCount]は右端に並ぶボタンの数、[titleFontSize]は題名の
/// 文字サイズ、[textScale]はアプリ全体の文字の拡大率。題名に約[kPaneTitleMinChars]文字ぶんの幅が
/// 残らなければtrue（ハンバーガーにまとめる）。
bool paneNeedsMenu({
  required double maxWidth,
  required int actionCount,
  required double titleFontSize,
  double textScale = 1,
}) {
  final titleMinWidth = titleFontSize * textScale * kPaneTitleMinChars;
  return maxWidth <
      actionCount * kPaneActionWidth + titleMinWidth + kPaneTitleRowPadding * 2;
}

/// ボタン群をまとめるハンバーガーメニュー（押して離す／なぞって選ぶ）。
/// アイコンはメッセージ画面のハンバーガーと同じくUIスタイルで出し分ける。
Widget paneHamburgerMenu<T>({
  required List<PressDragMenuItem<T>> items,
  required ValueChanged<T> onSelected,
  bool enabled = true,
}) {
  return PressDragMenuButton<T>(
    enabled: enabled,
    items: items,
    onSelected: onSelected,
    child: Consumer(
      builder: (context, ref, _) {
        final uiStyle = ref.watch(appUiStyleProvider);
        return IconButton(
          tooltip: '',
          icon: switch (uiStyle) {
            AppUiStyle.gekiga => const GekigaIconBadge(
              icon: Icons.menu,
              size: 32,
              seed: gekigaToolbarIconSeed,
            ),
            AppUiStyle.glass => const GlassIconBadge(
              icon: Icons.menu,
              size: 32,
              opaque: true,
            ),
            AppUiStyle.block => const BlockIconBadge(icon: Icons.menu),
            AppUiStyle.flat => const Icon(Icons.menu),
          },
          // 押下はPressDragMenuButton（Listener）が受ける。
          onPressed: enabled ? () {} : null,
        );
      },
    ),
  );
}
