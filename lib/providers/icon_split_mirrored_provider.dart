import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'iconSplitMirrored';

/// 語らい一覧の「アイコン＋寄合一覧」レイアウト（`TalksListLayoutStyle.iconSplit`）を
/// 左右反転するか（標準: オフ、2026-11-01）。オンなら、アイコン列が右端・メッセージ画面が
/// 左になり、寄合一覧との並びも逆になる。端末に保存されている初期値は`main()`で起動前に
/// 読み込んで渡す（未指定のテストでは標準のオフ）。
final initialIconSplitMirroredProvider = Provider<bool>((ref) => false);

Future<bool> loadInitialIconSplitMirrored() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? false;
}

class IconSplitMirroredNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialIconSplitMirroredProvider);

  Future<void> setMirrored(bool mirrored) async {
    state = mirrored;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, mirrored);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'iconSplitMirrored', mirrored);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(bool mirrored) async {
    state = mirrored;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, mirrored);
  }
}

final iconSplitMirroredProvider =
    NotifierProvider<IconSplitMirroredNotifier, bool>(
      IconSplitMirroredNotifier.new,
    );
