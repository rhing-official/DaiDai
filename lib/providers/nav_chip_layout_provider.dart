import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_chip_layout.dart';

const _alignmentKey = 'navChipAlignment';
const _orderKey = 'navChipOrder';

/// 端末に保存されている初期のメニューチップの揃え・並び（2026-11-01）。アカウントには保存せず、
/// 端末ごとに持つ（画面の幅や持ち方が端末で違うため。同日ユーザー指示）。main()で起動前に
/// 読み込んで渡す（未指定のテストでは標準）。
final initialNavChipLayoutProvider = Provider<NavChipLayout>(
  (ref) => NavChipLayout.standard,
);

Future<NavChipLayout> loadInitialNavChipLayout() async {
  final prefs = await SharedPreferences.getInstance();
  return NavChipLayout(
    alignment: NavChipAlignment.fromName(prefs.getString(_alignmentKey)),
    order: normalizeNavChipOrder(prefs.getStringList(_orderKey)),
  );
}

class NavChipLayoutNotifier extends Notifier<NavChipLayout> {
  @override
  NavChipLayout build() => ref.watch(initialNavChipLayoutProvider);

  Future<void> setAlignment(NavChipAlignment alignment) async {
    state = state.copyWith(alignment: alignment);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alignmentKey, alignment.name);
  }

  Future<void> setOrder(List<HomeTabId> order) async {
    final normalized = normalizeNavChipOrder([for (final t in order) t.name]);
    state = state.copyWith(order: normalized);
    final names = [for (final tab in normalized) tab.name];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, names);
  }
}

final navChipLayoutProvider =
    NotifierProvider<NavChipLayoutNotifier, NavChipLayout>(
      NavChipLayoutNotifier.new,
    );
