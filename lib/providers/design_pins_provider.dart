import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'designPins';

/// 端末に保存されている、ピン留めしたデザインのid。main()で起動前に読んで渡す。
/// overrideされない場合（テスト等）は、ピン留め無し。
final initialDesignPinsProvider = Provider<List<String>>((ref) => const []);

Future<List<String>> loadInitialDesignPins() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_prefsKey) ?? const [];
}

/// 設定>UIで、ピン留めしたデザイン（標準のスタイルも素材パックも）。留めた順。
/// 端末とアカウントの両方へ保存し、別の端末でも同じ並びにする。
class DesignPinsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(initialDesignPinsProvider);

  Future<void> toggle(String designId) async {
    state = state.contains(designId)
        ? [
            for (final id in state)
              if (id != designId) id,
          ]
        : [...state, designId];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'designPins', state);
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(List<String> pins) async {
    state = pins;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, pins);
  }
}

final designPinsProvider = NotifierProvider<DesignPinsNotifier, List<String>>(
  DesignPinsNotifier.new,
);
