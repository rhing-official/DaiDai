import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/terminology_style.dart';
import 'repository_providers.dart';

const _prefsKey = 'terminologyStyle';

/// 端末に保存されている初期の用語スタイル。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialTerminologyStyleProvider = Provider<TerminologyStyle>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<TerminologyStyle> loadInitialTerminologyStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return TerminologyStyle.fromName(prefs.getString(_prefsKey));
}

class TerminologyStyleNotifier extends Notifier<TerminologyStyle> {
  @override
  TerminologyStyle build() => ref.watch(initialTerminologyStyleProvider);

  Future<void> setStyle(TerminologyStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'terminologyStyle', style.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(TerminologyStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final terminologyStyleProvider =
    NotifierProvider<TerminologyStyleNotifier, TerminologyStyle>(
      TerminologyStyleNotifier.new,
    );
