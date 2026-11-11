import '../providers/text_size_provider.dart';

/// 設定・身だしなみ・語らい（コンピューター）のサイドバーの幅。3画面は区切り線のx座標を
/// そろえる為、全て[sidebarWidthFor]で幅を決める（2026-08-14に260pxで統一）。
///
/// 2026-11-06: フォントサイズ別に変える。以前の標準（260px）を「大」の幅とし、「小」「中」は
/// それより狭く定義した（小200・中230・大260）。
///
/// 2026-11-12: 語らいの「一対／広場」タブ行（`talks_tab.dart`）が小でも23px溢れた為（余白・
/// ボタン分を除くと90pxしか残らず、タブは約113px要る）、小230・中270・大310へ広げた。
const double kSidebarWidthSmall = 230.0;
const double kSidebarWidthMedium = 270.0;
const double kSidebarWidthLarge = 310.0;

/// フォントサイズ[size]に対応するサイドバーの標準幅。
double sidebarWidthFor(AppTextSize size) => switch (size) {
  AppTextSize.small => kSidebarWidthSmall,
  AppTextSize.medium => kSidebarWidthMedium,
  AppTextSize.large => kSidebarWidthLarge,
};
