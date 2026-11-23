import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_chip_layout.dart';

const _verticalPrefsKey = 'categoryListVertical';

/// 項目一覧の縦の位置（2026-11-07）。上か、下（メニューチップのすぐ上、標準。
/// 2026-11-15に上から変更）か、中央（2026-11-23追加）。全てのUIスタイルで効く。
/// 端末毎に保存する。（劇画UIだけにあった左右の揃えは2026-11-15に廃止。）
/// 2026-11-23、狭い画面（スマホ）だけでなく広い画面（タブレット・PCのサイドバー表示）
/// にも同じ設定を適用するよう一度変更したが、同日中に広い画面はナビチップの縦の揃え
/// （[NavChipAlignment]、`wideAlignment`）へ同期する方式に変更した（両者が同じ
/// 「上/中央/下」という軸になる為、広い画面専用の設定は持たない。[categoryListVerticalFromNavChipAlignment]
/// 参照）。この設定自体は狭い画面専用として引き続き端末毎に保存する。
enum CategoryListVertical {
  top,
  center,
  bottom;

  static CategoryListVertical fromName(String? name) => switch (name) {
    'top' => CategoryListVertical.top,
    'center' => CategoryListVertical.center,
    _ => CategoryListVertical.bottom,
  };
}

final initialCategoryListVerticalProvider = Provider<CategoryListVertical>(
  (ref) => CategoryListVertical.bottom,
);

Future<CategoryListVertical> loadInitialCategoryListVertical() async {
  final prefs = await SharedPreferences.getInstance();
  return CategoryListVertical.fromName(prefs.getString(_verticalPrefsKey));
}

class CategoryListVerticalNotifier extends Notifier<CategoryListVertical> {
  @override
  CategoryListVertical build() =>
      ref.watch(initialCategoryListVerticalProvider);

  Future<void> setVertical(CategoryListVertical value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verticalPrefsKey, value.name);
  }
}

final categoryListVerticalProvider =
    NotifierProvider<CategoryListVerticalNotifier, CategoryListVertical>(
      CategoryListVerticalNotifier.new,
    );

/// ナビチップの縦の揃え（広い画面用、[NavChipAlignment]）を項目一覧の縦の位置へ
/// 変換する（2026-11-23）。広い画面では項目一覧もナビチップと同じ「上/中央/下」の
/// 縦の位置を使うため、専用の設定は持たずここで変換するだけにする。
CategoryListVertical categoryListVerticalFromNavChipAlignment(
  NavChipAlignment alignment,
) => switch (alignment) {
  NavChipAlignment.start => CategoryListVertical.top,
  NavChipAlignment.center => CategoryListVertical.center,
  NavChipAlignment.end => CategoryListVertical.bottom,
};
