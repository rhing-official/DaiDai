import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'customBackgroundColorsArgb32';

/// ユーザーが自分で登録出来る、背景色のプリセットの上限数（2026-11-26）。
const kMaxCustomBackgroundColors = 5;

/// 端末に保存されている登録済みの背景色。`main()`で起動前に読み込んで渡す（未指定のテストでは空）。
final initialCustomBackgroundColorsProvider = Provider<List<Color>>(
  (ref) => const [],
);

Future<List<Color>> loadInitialCustomBackgroundColors() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getStringList(_prefsKey);
  if (saved == null) return const [];
  return saved.map((s) => Color(int.parse(s))).toList();
}

/// 登録した背景色（[customAccentColorsProvider]と同じ作り）。
class CustomBackgroundColorsNotifier extends Notifier<List<Color>> {
  @override
  List<Color> build() => ref.watch(initialCustomBackgroundColorsProvider);

  /// 上限に達している、又は既に登録済みの色なら、何もせず`false`を返す。
  Future<bool> addColor(Color color) async {
    final c = color.withAlpha(0xFF);
    if (state.length >= kMaxCustomBackgroundColors || state.contains(c)) {
      return false;
    }
    await _set([...state, c]);
    return true;
  }

  Future<void> removeColor(Color color) =>
      _set(state.where((c) => c != color).toList());

  Future<void> _set(List<Color> colors) async {
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
          'customBackgroundColorsArgb',
          colors.map((c) => c.toARGB32()).toList(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(List<Color> colors) async {
    state = colors;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      colors.map((c) => c.toARGB32().toString()).toList(),
    );
  }
}

final customBackgroundColorsProvider =
    NotifierProvider<CustomBackgroundColorsNotifier, List<Color>>(
      CustomBackgroundColorsNotifier.new,
    );
