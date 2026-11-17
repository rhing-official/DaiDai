import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'appThemeMode';

/// 端末に保存されている初期の外観設定（ライト/ダーク/端末に合わせる）。
/// main()で起動前に読み込み、ProviderScopeのoverrideとして渡す。
final initialAppThemeModeProvider = Provider<ThemeMode>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

/// 「端末に合わせる」は選択肢から廃止した（2026-11-18）。保存値が無い・古い
/// `system`の時は、その時点の端末の明るさでライトかダーク（標準）に決める。
ThemeMode resolveThemeMode(ThemeMode mode) {
  if (mode != ThemeMode.system) return mode;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
}

Future<ThemeMode> loadInitialAppThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_prefsKey);
  return resolveThemeMode(
    ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    ),
  );
}

class AppThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => resolveThemeMode(ref.watch(initialAppThemeModeProvider));

  Future<void> setMode(ThemeMode requested) async {
    final mode = resolveThemeMode(requested);
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'themeMode', mode.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(ThemeMode requested) async {
    final mode = resolveThemeMode(requested);
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final appThemeModeProvider = NotifierProvider<AppThemeModeNotifier, ThemeMode>(
  AppThemeModeNotifier.new,
);
