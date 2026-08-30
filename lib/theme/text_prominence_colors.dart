import 'package:flutter/material.dart';

import 'app_theme_extras.dart';
import 'glass/glass_theme_extras.dart';

/// テキスト・アイコンの「重要度階調」（2026-08-30追加）。Discordの
/// 「要素が小さくなるほど黒→灰色に薄くなる」配色を参考に、フラット・
/// ガラスのスタイルへ導入する。劇画は背景色がユーザー設定可能な色
/// （既定は赤）で、`fromSeed`任せの中間グレーが背景と衝突して視認性が
/// 落ちた経緯（`gekiga_theme.dart`参照）があるため対象外とし、白1色の
/// ままにする。
///
/// 段階は3つ: Primary（見出し・強調）/ Secondary（本文・通常アイコン、
/// `ColorScheme.onSurface`/`onSurfaceVariant`として各テーマに直接組み込む）
/// / Tertiary（補助・タイムスタンプ・ヒント・無効化アイコン、ColorScheme
/// に対応ロールが無いため各テーマの`ThemeExtension`経由で提供する）。
///
/// Primaryの値は既存の`GlassColors.lightForeground`/`darkForeground`と
/// 同じにしてあり、ガラスの見た目は変わらない（フラット側はこれまで
/// `fromSeed`由来のアクセントカラーの色相が乗っていたテキスト色が、
/// この導入で初めて中立色に固定される）。
class TextProminence {
  TextProminence._();

  static const darkPrimary = Color(0xFFF2F2F7);
  static const darkSecondary = Color(0xFFC2C2C8);
  static const darkTertiary = Color(0xFF87878F);

  static const lightPrimary = Color(0xFF1C1C1E);
  static const lightSecondary = Color(0xFF54545B);
  static const lightTertiary = Color(0xFF8B8B93);
}

/// Tier3（補助）の文字・アイコン色を、現在のUIスタイルに応じて取得する。
/// フラット/ガラスは各テーマの`ThemeExtension`（`AppThemeExtras`/
/// `GlassThemeExtras`）が保持する固定色を返す。劇画は対象外のため
/// フォールバックとして`colorScheme.onSurfaceVariant`を返すが、劇画分岐が
/// 既にある呼び出し元はそちらを使うべきで、通常この関数を劇画で呼ぶ
/// ことは想定していない。
Color resolveTertiaryTextColor(BuildContext context, {required bool isGlass}) {
  final theme = Theme.of(context);
  if (isGlass) {
    return theme.extension<GlassThemeExtras>()?.textTertiary ??
        theme.colorScheme.onSurfaceVariant;
  }
  return theme.extension<AppThemeExtras>()?.textTertiary ??
      theme.colorScheme.onSurfaceVariant;
}
