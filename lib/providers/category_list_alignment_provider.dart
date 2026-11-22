import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _verticalPrefsKey = 'categoryListVertical';

/// 項目一覧の縦の位置（2026-11-07）。上か、下（メニューチップのすぐ上、標準。
/// 2026-11-15に上から変更）か、中央（2026-11-23追加）。全てのUIスタイルで効く。
/// 端末毎に保存する。（劇画UIだけにあった左右の揃えは2026-11-15に廃止。）
/// 2026-11-23に、狭い画面（スマホ）だけでなく広い画面（タブレット・PCのサイドバー
/// 表示）にも同じ設定を適用するよう変更した。
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
