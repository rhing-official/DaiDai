import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_chip_layout.dart';
import 'repository_providers.dart';

const _alignmentKey = 'navChipAlignment';
const _orderKey = 'navChipOrder';

/// 端末に保存されている初期のメニューチップの揃え・並び（2026-11-01）。main()で起動前に
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
    await _syncToAccount('navChipAlignment', alignment.name);
  }

  Future<void> setOrder(List<HomeTabId> order) async {
    final normalized = normalizeNavChipOrder([for (final t in order) t.name]);
    state = state.copyWith(order: normalized);
    final names = [for (final tab in normalized) tab.name];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, names);
    await _syncToAccount('navChipOrder', names);
  }

  Future<void> _syncToAccount(String field, Object value) async {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, field, value);
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする（書き戻しはしない）。
  /// 引数がnullの項目は変えない。
  Future<void> syncFromRemote({
    String? alignmentName,
    List<String>? orderNames,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var next = state;
    if (alignmentName != null) {
      final alignment = NavChipAlignment.fromName(alignmentName);
      next = next.copyWith(alignment: alignment);
      await prefs.setString(_alignmentKey, alignment.name);
    }
    if (orderNames != null) {
      final order = normalizeNavChipOrder(orderNames);
      next = next.copyWith(order: order);
      await prefs.setStringList(_orderKey, [for (final t in order) t.name]);
    }
    state = next;
  }
}

final navChipLayoutProvider =
    NotifierProvider<NavChipLayoutNotifier, NavChipLayout>(
      NavChipLayoutNotifier.new,
    );
