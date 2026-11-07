import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _verticalPrefsKey = 'categoryListVertical';

/// スマホ（縦表示）の項目一覧の縦の位置（2026-11-07）。上（標準）か、下（メニューチップの
/// すぐ上）。全てのUIスタイルで効く。端末毎に保存する。
/// （劇画UIだけにあった左右の揃えは同日廃止。）
enum CategoryListVertical {
  top,
  bottom;

  static CategoryListVertical fromName(String? name) =>
      name == 'bottom' ? CategoryListVertical.bottom : CategoryListVertical.top;
}

final initialCategoryListVerticalProvider = Provider<CategoryListVertical>(
  (ref) => CategoryListVertical.top,
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
