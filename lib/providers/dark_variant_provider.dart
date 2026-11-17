import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dark_variant.dart';
import 'repository_providers.dart';

const _prefsKey = 'appDarkVariant';

/// 端末に保存されている初期のダークの種類。main()で起動前に読み込んでoverrideする（未指定は標準）。
final initialDarkVariantProvider = Provider<DarkVariant>(
  (ref) => DarkVariant.standard,
);

Future<DarkVariant> loadInitialDarkVariant() async {
  final prefs = await SharedPreferences.getInstance();
  return DarkVariant.fromName(prefs.getString(_prefsKey));
}

class DarkVariantNotifier extends Notifier<DarkVariant> {
  @override
  DarkVariant build() => ref.watch(initialDarkVariantProvider);

  Future<void> setVariant(DarkVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, variant.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'darkVariant', variant.name);
  }

  /// ログイン時、Firestoreの値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(DarkVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, variant.name);
  }
}

final darkVariantProvider = NotifierProvider<DarkVariantNotifier, DarkVariant>(
  DarkVariantNotifier.new,
);
