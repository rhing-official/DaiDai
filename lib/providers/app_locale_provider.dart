import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import 'repository_providers.dart';

const _prefsKey = 'appLocaleLanguageCode';

/// 端末に保存されている初期表示言語。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialAppLocaleProvider = Provider<AppLocale>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<AppLocale> loadInitialAppLocale() async {
  final prefs = await SharedPreferences.getInstance();
  return AppLocale.fromLanguageCode(prefs.getString(_prefsKey));
}

class AppLocaleNotifier extends Notifier<AppLocale> {
  @override
  AppLocale build() => ref.watch(initialAppLocaleProvider);

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'localeCode', locale.languageCode);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(AppLocale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleNotifier, AppLocale>(
  AppLocaleNotifier.new,
);
