import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'fontPins';

/// 端末に保存されている、ピン留めしたフォントデザインの名前（`FontDesign.name`）。main()で
/// 起動前に読んで渡す。overrideされない場合（テスト等）は、ピン留め無し。
final initialFontPinsProvider = Provider<List<String>>((ref) => const []);

Future<List<String>> loadInitialFontPins() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_prefsKey) ?? const [];
}

/// 設定>フォントデザインで、ピン留めしたフォント。留めた順。端末とアカウントの両方へ保存し、
/// 別の端末でも同じ並びにする（[DesignPinsNotifier]と同じ作り）。
class FontPinsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(initialFontPinsProvider);

  Future<void> toggle(String fontName) async {
    state = state.contains(fontName)
        ? [
            for (final n in state)
              if (n != fontName) n,
          ]
        : [...state, fontName];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'fontPins', state);
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(List<String> pins) async {
    state = pins;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, pins);
  }
}

final fontPinsProvider = NotifierProvider<FontPinsNotifier, List<String>>(
  FontPinsNotifier.new,
);
