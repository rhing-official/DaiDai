import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'removedDefaultColorPresetsHex';

/// 端末に保存されている「削除済みの固定プリセット」の初期値。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （[initialCustomAccentColorsProvider]と同じパターン）。
final initialRemovedDefaultColorPresetsProvider = Provider<Set<String>>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Set<String>> loadInitialRemovedDefaultColorPresets() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList(_prefsKey);
  if (saved == null) return const {};
  return saved.toSet();
}

/// 開発側が用意した固定プリセット（アクセントカラー設定の
/// `_kDefaultColorPresets`）のうち、ユーザーが長押しで削除した色の
/// hex文字列集合。復活させる手段は意図的に設けない方針のため、削除の
/// 取り消しAPIは無い（追加のみ）。
class RemovedDefaultColorPresetsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(initialRemovedDefaultColorPresetsProvider);

  Future<void> markRemoved(String hex) async {
    if (state.contains(hex)) return;
    await _setHexes({...state, hex});
  }

  Future<void> _setHexes(Set<String> hexes) async {
    state = hexes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, hexes.toList());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(
          userId,
          'removedDefaultColorPresetsHex',
          hexes.toList(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない、[CustomAccentColorsNotifier]
  /// と同じ方針）。
  Future<void> syncFromRemote(Set<String> hexes) async {
    state = hexes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, hexes.toList());
  }
}

final removedDefaultColorPresetsProvider =
    NotifierProvider<RemovedDefaultColorPresetsNotifier, Set<String>>(
      RemovedDefaultColorPresetsNotifier.new,
    );
