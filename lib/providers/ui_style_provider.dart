import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ui_style.dart';

const _prefsKey = 'uiStyle';

/// 端末に保存されている初期UIスタイル。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialUiStyleProvider = Provider<UiStyle>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<UiStyle> loadInitialUiStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return UiStyle.fromName(prefs.getString(_prefsKey));
}

class UiStyleNotifier extends Notifier<UiStyle> {
  @override
  UiStyle build() => ref.watch(initialUiStyleProvider);

  Future<void> setStyle(UiStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final uiStyleProvider = NotifierProvider<UiStyleNotifier, UiStyle>(
  UiStyleNotifier.new,
);
