import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'joinVideoCameraOn';

/// ビデオ通話に応答・参加した時、カメラをオンにして入るか（標準: オン、2026-11-01）。
/// オフなら音声のみ（カメラを切った状態）で入り、通話中にいつでもオンに出来る。
/// 自分から発信する1対1のビデオ通話には影響しない。端末に保存されている初期値は
/// main()で起動前に読み込んで渡す（未指定のテストでは標準のオン）。
final initialJoinVideoCameraOnProvider = Provider<bool>((ref) => true);

Future<bool> loadInitialJoinVideoCameraOn() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? true;
}

class JoinVideoCameraOnNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialJoinVideoCameraOnProvider);

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'joinVideoCameraOn', enabled);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }
}

final joinVideoCameraOnProvider =
    NotifierProvider<JoinVideoCameraOnNotifier, bool>(
      JoinVideoCameraOnNotifier.new,
    );
