import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'appThemeMode';

/// 端末に保存されている初期の外観設定（ライト/ダーク/端末に合わせる）。
/// main()で起動前に読み込み、ProviderScopeのoverrideとして渡す。
final initialAppThemeModeProvider = Provider<ThemeMode>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<ThemeMode> loadInitialAppThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_prefsKey);
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.system,
  );
}

class AppThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialAppThemeModeProvider);

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final appThemeModeProvider = NotifierProvider<AppThemeModeNotifier, ThemeMode>(
  AppThemeModeNotifier.new,
);
