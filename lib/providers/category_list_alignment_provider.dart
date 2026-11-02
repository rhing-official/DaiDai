import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_chip_layout.dart';

const _prefsKey = 'categoryListAlignment';

/// スマホの項目一覧（設定・身だしなみのカテゴリ一覧）を左寄せ・中央（標準）・右寄せにする
/// 設定（2026-11-02）。メニューチップの揃えと同じ`NavChipAlignment`を使い、アカウントには
/// 保存せず端末ごとに持つ。端末の保存値は`main()`で起動前に読み込んで渡す。
final initialCategoryListAlignmentProvider = Provider<NavChipAlignment>(
  (ref) => NavChipAlignment.center,
);

Future<NavChipAlignment> loadInitialCategoryListAlignment() async {
  final prefs = await SharedPreferences.getInstance();
  return NavChipAlignment.fromName(prefs.getString(_prefsKey));
}

class CategoryListAlignmentNotifier extends Notifier<NavChipAlignment> {
  @override
  NavChipAlignment build() => ref.watch(initialCategoryListAlignmentProvider);

  Future<void> setAlignment(NavChipAlignment alignment) async {
    state = alignment;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, alignment.name);
  }
}

final categoryListAlignmentProvider =
    NotifierProvider<CategoryListAlignmentNotifier, NavChipAlignment>(
      CategoryListAlignmentNotifier.new,
    );
