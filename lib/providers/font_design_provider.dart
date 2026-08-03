import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/font_design.dart';
import 'repository_providers.dart';

const _prefsKey = 'fontDesign';

/// 端末に保存されている初期のフォントデザイン。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialFontDesignProvider = Provider<FontDesign>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<FontDesign> loadInitialFontDesign() async {
  final prefs = await SharedPreferences.getInstance();
  return FontDesign.fromName(prefs.getString(_prefsKey));
}

class FontDesignNotifier extends Notifier<FontDesign> {
  @override
  FontDesign build() => ref.watch(initialFontDesignProvider);

  Future<void> setDesign(FontDesign design) async {
    state = design;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, design.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'fontDesign', design.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(FontDesign design) async {
    state = design;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, design.name);
  }
}

final fontDesignProvider = NotifierProvider<FontDesignNotifier, FontDesign>(
  FontDesignNotifier.new,
);
