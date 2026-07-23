import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'accentColorArgb32';

/// ユーザーが未設定の場合に使う既定のアクセントカラー。
const kDefaultAccentColor = Color(0xFFF08300);

/// 端末に保存されている初期アクセントカラー。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialAccentColorProvider = Provider<Color>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Color> loadInitialAccentColor() async {
  final prefs = await SharedPreferences.getInstance();
  final argb32 = prefs.getInt(_prefsKey);
  return argb32 == null ? kDefaultAccentColor : Color(argb32);
}

class AccentColorNotifier extends Notifier<Color> {
  @override
  Color build() => ref.watch(initialAccentColorProvider);

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, color.toARGB32());
  }
}

final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);
