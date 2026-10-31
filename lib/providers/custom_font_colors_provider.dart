import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'customFontColorsArgb32';

/// ユーザーが自分で登録できるカードの文字色の上限数（2026-10-31追加）。
const kMaxCustomFontColors = 5;

/// 端末に保存されているカードの文字色の登録色の初期値。main()で起動前に
/// 読み込み、ProviderScopeのoverrideとして渡す（[accentColorProvider]と
/// 同じパターン）。
final initialCustomFontColorsProvider = Provider<List<Color>>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<List<Color>> loadInitialCustomFontColors() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList(_prefsKey);
  if (saved == null) return const [];
  return saved.map((s) => Color(int.parse(s))).toList();
}

class CustomFontColorsNotifier extends Notifier<List<Color>> {
  @override
  List<Color> build() => ref.watch(initialCustomFontColorsProvider);

  /// 上限（[kMaxCustomFontColors]）に達している、または既に登録済みの
  /// 色の場合は何もせず`false`を返す。
  Future<bool> addColor(Color color) async {
    if (state.length >= kMaxCustomFontColors || state.contains(color)) {
      return false;
    }
    await _setColors([...state, color]);
    return true;
  }

  Future<void> removeColor(Color color) async {
    await _setColors(state.where((c) => c != color).toList());
  }

  Future<void> _setColors(List<Color> colors) async {
    state = colors;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      colors.map((c) => c.toARGB32().toString()).toList(),
    );
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(
          userId,
          'customFontColorsArgb',
          colors.map((c) => c.toARGB32()).toList(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない、[accentColorProvider]
  /// と同じ方針）。
  Future<void> syncFromRemote(List<Color> colors) async {
    state = colors;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      colors.map((c) => c.toARGB32().toString()).toList(),
    );
  }
}

final customFontColorsProvider =
    NotifierProvider<CustomFontColorsNotifier, List<Color>>(
      CustomFontColorsNotifier.new,
    );
