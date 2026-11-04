import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/slide_transition_style.dart';
import '../theme/motion.dart';
import 'repository_providers.dart';

const _prefsKey = 'slideTransitionStyle';

/// 端末に保存されている初期の画面遷移の種類。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialSlideTransitionStyleProvider = Provider<SlideTransitionStyle>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<SlideTransitionStyle> loadInitialSlideTransitionStyle() async {
  final prefs = await SharedPreferences.getInstance();
  final style = SlideTransitionStyle.fromName(prefs.getString(_prefsKey));
  activeSlideTransitionStyle = style;
  return style;
}

class SlideTransitionStyleNotifier extends Notifier<SlideTransitionStyle> {
  @override
  SlideTransitionStyle build() {
    final style = ref.watch(initialSlideTransitionStyleProvider);
    activeSlideTransitionStyle = style;
    return style;
  }

  Future<void> setStyle(SlideTransitionStyle style) async {
    state = style;
    // 遷移の組み立て関数は`ref`を持たないため、`motion.dart`の変数へも反映する。
    activeSlideTransitionStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'slideTransitionStyle', style.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(SlideTransitionStyle style) async {
    state = style;
    activeSlideTransitionStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final slideTransitionStyleProvider =
    NotifierProvider<SlideTransitionStyleNotifier, SlideTransitionStyle>(
      SlideTransitionStyleNotifier.new,
    );
