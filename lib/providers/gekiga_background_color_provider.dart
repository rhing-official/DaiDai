import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/gekiga/gekiga_colors.dart';
import 'repository_providers.dart';

const _prefsKey = 'gekigaBackgroundColorArgb32';

/// ユーザーが未設定の場合に使う劇画UIの既定の背景色（現在の赤）。
const kDefaultGekigaBackgroundColor = GekigaColors.background;

/// 端末に保存されている初期の劇画UI背景色。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialGekigaBackgroundColorProvider = Provider<Color>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Color> loadInitialGekigaBackgroundColor() async {
  final prefs = await SharedPreferences.getInstance();
  final argb32 = prefs.getInt(_prefsKey);
  return argb32 == null ? kDefaultGekigaBackgroundColor : Color(argb32);
}

class GekigaBackgroundColorNotifier extends Notifier<Color> {
  @override
  Color build() => ref.watch(initialGekigaBackgroundColorProvider);

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, color.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(
          userId,
          'gekigaBackgroundColorArgb',
          color.toARGB32(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, color.toARGB32());
  }
}

final gekigaBackgroundColorProvider =
    NotifierProvider<GekigaBackgroundColorNotifier, Color>(
      GekigaBackgroundColorNotifier.new,
    );
