import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sticker_send_mode.dart';
import 'repository_providers.dart';

const _prefsKey = 'stickerSendMode';

/// 端末に保存されている初期のペタピタ送信方式設定。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialStickerSendModeProvider = Provider<StickerSendMode>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<StickerSendMode> loadInitialStickerSendMode() async {
  final prefs = await SharedPreferences.getInstance();
  return StickerSendMode.fromName(prefs.getString(_prefsKey));
}

class StickerSendModeNotifier extends Notifier<StickerSendMode> {
  @override
  StickerSendMode build() => ref.watch(initialStickerSendModeProvider);

  Future<void> setMode(StickerSendMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'stickerSendMode', mode.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(StickerSendMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final stickerSendModeProvider =
    NotifierProvider<StickerSendModeNotifier, StickerSendMode>(
      StickerSendModeNotifier.new,
    );
