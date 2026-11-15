import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'micDenoiseEnabled';

/// 通話のマイクのノイズ除去（RNNoise、Webのみ）を使うか（2026-11-15）。端末毎に保存し、
/// 既定はオン。通話の開始時に読むので、変更は次の通話から効く。
Future<bool> loadMicDenoiseEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefsKey) ?? true;
}

class MicDenoiseNotifier extends Notifier<bool> {
  @override
  bool build() {
    loadMicDenoiseEnabled().then((value) {
      if (ref.mounted) state = value;
    });
    return true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

final micDenoiseProvider = NotifierProvider<MicDenoiseNotifier, bool>(
  MicDenoiseNotifier.new,
);
