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
  return argb32 == null
      ? kDefaultGekigaBackgroundColor
      : Color(argb32).withAlpha(0xFF);
}

class GekigaBackgroundColorNotifier extends Notifier<Color> {
  @override
  Color build() => ref.watch(initialGekigaBackgroundColorProvider);

  /// 劇画UIの背景色は常に不透明として扱う（2026-09-15追加）。
  /// `tryParseHexColor`は8桁（透明度付き）のカラーコードもパースできるが、
  /// 劇画UIの吹き出し・パネル類の大半は`GekigaColors.panel`/`onPanel`と
  /// いう不透明な固定色で構成されている一方、背景色は`GekigaTheme.build`で
  /// `surface`/`scaffoldBackgroundColor`等へそのまま適用されるため、透明度を
  /// 持たせると画面によって見え方が食い違う不具合があった。読み込み・保存の
  /// 発生源（ここ）で一律アルファを固定することで、消費側は常に不透明な値
  /// として扱ってよいことを保証する。
  Future<void> setColor(Color color) async {
    final opaque = color.withAlpha(0xFF);
    state = opaque;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, opaque.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(
          userId,
          'gekigaBackgroundColorArgb',
          opaque.toARGB32(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(Color color) async {
    final opaque = color.withAlpha(0xFF);
    state = opaque;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, opaque.toARGB32());
  }
}

final gekigaBackgroundColorProvider =
    NotifierProvider<GekigaBackgroundColorNotifier, Color>(
      GekigaBackgroundColorNotifier.new,
    );
