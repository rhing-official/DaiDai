import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'ringtoneSound';

/// 端末に保存されている初期の着信音設定（プリセットIDまたはカスタム
/// アップロード音源のURL、未設定ならnull＝既定プリセット）。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （`font_design_provider.dart`と同じパターン、2026-09-06追加）。
final initialRingtoneSoundProvider = Provider<String?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<String?> loadInitialRingtoneSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

class RingtoneSoundNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialRingtoneSoundProvider);

  Future<void> setSound(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'ringtoneSound', value);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
  }
}

final ringtoneSoundProvider = NotifierProvider<RingtoneSoundNotifier, String?>(
  RingtoneSoundNotifier.new,
);
