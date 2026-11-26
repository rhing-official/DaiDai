import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'selectionWaterMotion';

/// 選択色を水が流れ込むように移すか（2026-11-26、標準: オン）。オフなら、メニューチップ・
/// 設定・身だしなみの一覧・語らいのタブは、従来どおり即時に切り替わる。保存が無い時は、
/// OSの「動きを減らす」設定がオンなら、オフから始める。
final initialSelectionWaterMotionProvider = Provider<bool>((ref) => true);

Future<bool> loadInitialSelectionWaterMotion() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ??
      !PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
}

class SelectionWaterMotionNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialSelectionWaterMotionProvider);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'selectionWaterMotion', enabled);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

final selectionWaterMotionProvider =
    NotifierProvider<SelectionWaterMotionNotifier, bool>(
      SelectionWaterMotionNotifier.new,
    );
