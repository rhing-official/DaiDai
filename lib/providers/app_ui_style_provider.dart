import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_ui_style.dart';
import 'repository_providers.dart';

const _prefsKey = 'appUiStyle';

/// 端末に保存されている初期のUIスタイル。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialAppUiStyleProvider = Provider<AppUiStyle>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<AppUiStyle> loadInitialAppUiStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return AppUiStyle.fromName(prefs.getString(_prefsKey));
}

class AppUiStyleNotifier extends Notifier<AppUiStyle> {
  @override
  AppUiStyle build() => ref.watch(initialAppUiStyleProvider);

  Future<void> setStyle(AppUiStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'appUiStyle', style.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(AppUiStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final appUiStyleProvider = NotifierProvider<AppUiStyleNotifier, AppUiStyle>(
  AppUiStyleNotifier.new,
);
