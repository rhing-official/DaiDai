import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/talks_list_layout_style.dart';
import 'repository_providers.dart';

const _prefsKey = 'talksListLayoutStyle';

/// 端末に保存されている初期の語らい一覧レイアウト。main()で起動前に読み込み、
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
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'talksListLayoutStyle', style.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(TalksListLayoutStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final talksListLayoutStyleProvider =
    NotifierProvider<TalksListLayoutStyleNotifier, TalksListLayoutStyle>(
      TalksListLayoutStyleNotifier.new,
    );
