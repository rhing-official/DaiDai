import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'callingSound';

/// 端末に保存されている初期の呼出音設定（プリセットIDまたはカスタム
/// アップロード音源のURL、未設定ならnull＝既定プリセット）。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （`ringtone_sound_provider.dart`と同じパターン、2026-09-06追加）。
final initialCallingSoundProvider = Provider<String?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<String?> loadInitialCallingSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

class CallingSoundNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialCallingSoundProvider);

  Future<void> setSound(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'callingSound', value);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
  }
}

final callingSoundProvider = NotifierProvider<CallingSoundNotifier, String?>(
  CallingSoundNotifier.new,
);
