import 'package:flutter/material.dart';

/// アルバム・ノート（マークダウン・ドロー）のペイン上部で、幅が狭い時に「メニュー（ボタン）の行」と
/// 「題名の行」を分けるための部品（2026-11-10、ユーザー指示）。
///
/// 縦画面の狭いペインでは、題名の入力欄がボタンの幅を引いた残りしか使えず、題名が途中で切れる。
/// 題名の文字サイズは中（アプリの文字サイズ設定・題名欄の指定）で決めているので縮めず、
/// 狭い時だけ`AppBar`を2段（1段目＝ボタン、2段目＝題名）にする。

/// ボタン1つぶんの幅（`IconButton`の既定）。
const double kPaneActionWidth = 48;

/// 題名に最低でも残したい文字数（これだけ入らなければ2段にする）。
const double kPaneTitleMinChars = 9;

/// 題名の行（2段目）の左右の余白（`AppBar`の`titleSpacing`と同じ）。
const double kPaneTitleRowPadding = 16;

/// 題名の行が1行目のボタンと同じ行に収まらないか。
///
/// [maxWidth]はペイン自身の幅、[actionCount]は右端に並ぶボタンの数、[titleFontSize]は題名の
/// 文字サイズ、[textScale]はアプリ全体の文字の拡大率。題名に約[kPaneTitleMinChars]文字ぶんの幅が
/// 残らなければtrue（2段にする）。
bool paneNeedsTitleRow({
  required double maxWidth,
  required int actionCount,
  required double titleFontSize,
  double textScale = 1,
}) {
  final titleMinWidth = titleFontSize * textScale * kPaneTitleMinChars;
  return maxWidth <
      actionCount * kPaneActionWidth + titleMinWidth + kPaneTitleRowPadding * 2;
}

/// 題名の行（`AppBar.bottom`に渡す）。高さは題名の文字サイズ（文字の拡大率込み）に追従する。
PreferredSizeWidget paneTitleRowBottom({
  required BuildContext context,
  required Widget titleField,
  required double titleFontSize,
}) {
  final scaled = MediaQuery.textScalerOf(context).scale(titleFontSize);
  final height = (scaled * 1.4 + 24).clamp(kToolbarHeight, double.infinity);
  return PreferredSize(
    preferredSize: Size.fromHeight(height),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kPaneTitleRowPadding),
        child: SizedBox(
          height: height,
          child: Center(child: titleField),
        ),
      ),
    ),
  );
}
