/// 劇画UIスタイルで使うフォントファミリー名の定数。
///
/// `pubspec.yaml`側のfont family名と一致させる必要があるため、テーマ
/// （[GekigaTheme]）と共通ウィジェット（`GekigaMenuTile`/`GekigaLabelChip`）の
/// 両方から同じ文字列を参照できるよう1箇所にまとめる（2026-08-03新規）。
class GekigaFonts {
  GekigaFonts._();

  /// フォントデザイン設定の「劇画」選択時に見出し・メニューへ当てるフォント
  /// （Persona5MenuFontPrototype-Regular、英数字専用でCJKグリフを持たない）。
  static const menuFontFamily = '劇画';
}
