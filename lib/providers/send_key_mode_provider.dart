import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/send_key_mode.dart';

const _prefsKey = 'sendKeyMode';

/// 端末に保存されている初期の送信キー設定。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialSendKeyModeProvider = Provider<SendKeyMode>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<SendKeyMode> loadInitialSendKeyMode() async {
  final prefs = await SharedPreferences.getInstance();
  return SendKeyMode.fromName(prefs.getString(_prefsKey));
}

class SendKeyModeNotifier extends Notifier<SendKeyMode> {
  @override
  SendKeyMode build() => ref.watch(initialSendKeyModeProvider);

  Future<void> setMode(SendKeyMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final sendKeyModeProvider = NotifierProvider<SendKeyModeNotifier, SendKeyMode>(
  SendKeyModeNotifier.new,
);
