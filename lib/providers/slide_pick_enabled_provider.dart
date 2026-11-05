import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'slidePickEnabled';

/// 「押したまま指を滑らせて選ぶ」操作を使うか（標準: オン、2026-11-05）。オフなら、
/// メニューチップ・語らいのボタンから別の項目・ボタン・チップへ滑らせる操作
/// （`ItemPickBridge`、`PickZone`）を止め、1回ずつのタップだけで操作する。チップの帯を
/// なぞってタブを切り替える動き（`HomeScreen`の`_handleSwipeUpdate`）は対象外。
/// 端末に保存されている初期値は`main()`で起動前に読み込んで渡す（未指定のテストでは
/// 標準のオン）。
final initialSlidePickEnabledProvider = Provider<bool>((ref) => true);

Future<bool> loadInitialSlidePickEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? true;
}

class SlidePickEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialSlidePickEnabledProvider);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'slidePickEnabled', enabled);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

final slidePickEnabledProvider =
    NotifierProvider<SlidePickEnabledNotifier, bool>(
      SlidePickEnabledNotifier.new,
    );
