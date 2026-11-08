import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_ui_style.dart';
import 'app_ui_style_provider.dart';
import 'repository_providers.dart';

const _prefsKey = 'accentColorArgb32';

/// ユーザーが未設定の場合に使う既定のアクセントカラー。
// 2026-10-31: #A997C6（アルファCC）。8桁hex表記ではA997C6CC。
const kDefaultAccentColor = Color(0xCCA997C6);

/// 端末に保存されている、UIスタイル別にする前の（共通の）アクセントカラー。
/// main()で起動前に読み込み、ProviderScopeのoverrideとして渡す。スタイル別の値が
/// まだ無いスタイルは、この色から始める（2026-11-08、UIスタイル毎の個別保存に
/// 変えた際に、既存の住人の色が変わらないようにする為）。
final initialAccentColorProvider = Provider<Color>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Color> loadInitialAccentColor() async {
  final prefs = await SharedPreferences.getInstance();
  final argb32 = prefs.getInt(_prefsKey);
  return argb32 == null ? kDefaultAccentColor : Color(argb32);
}

String _styleKey(AppUiStyle style) => '${_prefsKey}_${style.name}';

/// 端末に保存されているUIスタイル別のアクセントカラー（2026-11-08）。保存値が
/// 無いスタイルは含めない（[initialAccentColorProvider]に従う）。
final initialAccentColorsByStyleProvider = Provider<Map<AppUiStyle, Color>>(
  (ref) => const {},
);

Future<Map<AppUiStyle, Color>> loadInitialAccentColorsByStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    for (final style in AppUiStyle.values)
      if (prefs.getInt(_styleKey(style)) case final argb32?)
        style: Color(argb32),
  };
}

/// アクセントカラー。**UIスタイル毎に別々に保存する**（2026-11-08）。値は今の
/// UIスタイル（[appUiStyleProvider]）の色で、スタイルを切り替えるとそのスタイルで
/// 最後に選んだ色に替わる。保存値が無いスタイルは共通の旧値（無ければ既定色）から
/// 始める。劇画は専用の背景色（`gekigaBackgroundColorProvider`）を使い、ここは見ない。
class AccentColorNotifier extends Notifier<Color> {
  // スタイル別の色。Notifier自体は[build]の再実行（スタイルの切替）をまたいで
  // 残るので、ここに持てば切り替えても失われない。
  late final Map<AppUiStyle, Color> _colors = {
    ...ref.read(initialAccentColorsByStyleProvider),
  };

  Color _colorFor(AppUiStyle style) =>
      _colors[style] ?? ref.read(initialAccentColorProvider);

  @override
  Color build() => _colorFor(ref.watch(appUiStyleProvider));

  Future<void> setColor(Color color) async {
    final style = ref.read(appUiStyleProvider);
    _colors[style] = color;
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_styleKey(style), color.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(
          userId,
          'accentColorsArgb.${style.name}',
          color.toARGB32(),
        );
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。[byStyle]はスタイル名→色、
  /// [legacy]はスタイル別にする前の共通の1色（スタイル別の値が無いスタイルだけに使う）。
  Future<void> syncFromRemote({Map<String, int>? byStyle, int? legacy}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final style in AppUiStyle.values) {
      final argb32 = byStyle?[style.name];
      if (argb32 != null) {
        _colors[style] = Color(argb32);
        await prefs.setInt(_styleKey(style), argb32);
      } else if (legacy != null && !_colors.containsKey(style)) {
        _colors[style] = Color(legacy);
      }
    }
    state = _colorFor(ref.read(appUiStyleProvider));
  }
}

final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);
