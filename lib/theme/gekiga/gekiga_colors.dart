import 'package:flutter/material.dart';

/// 劇画UIスタイルの固定パレット。アクセントカラー（[accentColorProvider]）
/// とは独立の、このスタイル専用の色。ライト/ダークいずれのthemeModeでも
/// 常にこの配色になる（chat_screen.dartの既存実装からの踏襲方針、
/// 2026-07-30にアプリ全体へ拡張するタイミングで共有場所へ昇格）。
class GekigaColors {
  GekigaColors._();

  /// 全画面共通の背景色の既定値（旧 chat_screen.dart の
  /// `_kGekigaBackground`）。2026-08-05より、実際に描画される背景色は
  /// ユーザーが設定タブから編集できる`gekigaBackgroundColorProvider`側の
  /// 値（初期値はこの定数と同じ）を使う。この定数自体はその既定値・
  /// プリセット（設定タブの`_kGekigaBackgroundColorPresets`先頭）として
  /// 残す。
  static const background = Color(0xFFC1272D);

  /// 黒パネル・ラベルチップ・吹き出し(相手)の下地。
  static const panel = Colors.black;

  /// 白文字・白リング・吹き出し(自分)の下地。
  static const onPanel = Colors.white;

  /// ハーフトーン・ダイアゴナルアクセントに使う、背景より少し暗い赤
  /// （背景と同系色の陰影として重ねても馴染むように、背景色から算出せず
  /// 固定値で用意する）。
  static const shade = Color(0xFF8E1B20);
}
