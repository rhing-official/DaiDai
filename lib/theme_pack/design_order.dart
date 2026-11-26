import '../models/app_ui_style.dart';

/// 設定>UIの「デザイン」（標準のスタイルと、購入した素材パック）の並べ方（2026-11-26）。
///
/// 上から「選択中 → ピン留め → 購入したデザイン → 標準の並び」。
/// デザインは、`style:<AppUiStyle名>`と`pack:<パックid>`の文字列で見分ける。

/// 標準のスタイルの、並びの既定。
const List<AppUiStyle> kStandardDesignOrder = [
  AppUiStyle.block,
  AppUiStyle.chalk,
  AppUiStyle.glass,
  AppUiStyle.washi,
  AppUiStyle.flat,
  AppUiStyle.gekiga,
];

/// 一覧の上から数えて、この数までは常に見せる。残りは折りたたむ。
const int kDesignVisibleCount = 3;

String styleDesignId(AppUiStyle style) => 'style:${style.name}';
String packDesignId(String packId) => 'pack:$packId';

/// [ownedPackIds]は、購入した素材パックのid。新しく購入した順に渡す。
/// [pins]はピン留めしたデザインのidで、留めた順。存在しないidは無視する。
List<String> sortDesignIds({
  required String selectedId,
  required List<String> pins,
  required List<String> ownedPackIds,
}) {
  final available = <String>{
    for (final s in kStandardDesignOrder) styleDesignId(s),
    for (final id in ownedPackIds) packDesignId(id),
  };
  final out = <String>[];
  void add(String id) {
    if (available.contains(id) && !out.contains(id)) out.add(id);
  }

  add(selectedId);
  pins.forEach(add);
  for (final id in ownedPackIds) {
    add(packDesignId(id));
  }
  for (final s in kStandardDesignOrder) {
    add(styleDesignId(s));
  }
  return out;
}
