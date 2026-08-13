import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'draftSyncEnabled';

/// メッセージ入力欄の下書きを複数端末で同期するか（標準: オン）。
/// 端末に保存されている初期値。main()で起動前に読み込み、ProviderScopeの
/// overrideとして渡す。
final initialDraftSyncEnabledProvider = Provider<bool>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<bool> loadInitialDraftSyncEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? true;
}

class DraftSyncEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialDraftSyncEnabledProvider);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'draftSyncEnabled', enabled);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

final draftSyncEnabledProvider =
    NotifierProvider<DraftSyncEnabledNotifier, bool>(
      DraftSyncEnabledNotifier.new,
    );
