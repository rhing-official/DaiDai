import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/talks_list_layout_style.dart';

const _prefsKey = 'talksListLayoutStyle';

/// 端末に保存されている初期の語らい一覧レイアウト。アカウントには保存せず端末ごとに持つ
/// （2026-11-01、ユーザー指示。端末の画面の大きさで向く並びが違うため）。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialTalksListLayoutStyleProvider = Provider<TalksListLayoutStyle>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<TalksListLayoutStyle> loadInitialTalksListLayoutStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return TalksListLayoutStyle.fromName(prefs.getString(_prefsKey));
}

class TalksListLayoutStyleNotifier extends Notifier<TalksListLayoutStyle> {
  @override
  TalksListLayoutStyle build() =>
      ref.watch(initialTalksListLayoutStyleProvider);

  Future<void> setStyle(TalksListLayoutStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final talksListLayoutStyleProvider =
    NotifierProvider<TalksListLayoutStyleNotifier, TalksListLayoutStyle>(
      TalksListLayoutStyleNotifier.new,
    );
