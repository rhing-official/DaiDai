import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 着信音・呼出音を鳴らすか（2026-11-18、端末ごと、既定オン）。端末のみに保存し、Firestoreへは
/// 同期しない（電車の中など、場所によって端末ごとに変えたい設定のため）。
/// `callRingtoneEnabled`は、Androidの着信通知（`CallNotifications.kt`）も同じキーを読んで、
/// 音と振動を止める（FlutterのSharedPreferencesは`flutter.`付きで同じファイルに入る）。
const _ringtonePrefsKey = 'callRingtoneEnabled';
const _ringbackPrefsKey = 'callRingbackEnabled';

final initialCallRingtoneEnabledProvider = Provider<bool>((ref) => true);
final initialCallRingbackEnabledProvider = Provider<bool>((ref) => true);

Future<bool> loadInitialCallRingtoneEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_ringtonePrefsKey) ?? true;
}

Future<bool> loadInitialCallRingbackEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_ringbackPrefsKey) ?? true;
}

class _EnabledNotifier extends Notifier<bool> {
  _EnabledNotifier(this._initial, this._key);

  final Provider<bool> _initial;
  final String _key;

  @override
  bool build() => ref.watch(_initial);

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// 着信音（かかってきた通話の音。Androidは着信通知の音・振動も）。
final callRingtoneEnabledProvider = NotifierProvider<_EnabledNotifier, bool>(
  () => _EnabledNotifier(initialCallRingtoneEnabledProvider, _ringtonePrefsKey),
);

/// 呼出音（自分がかけている間に聞こえる音）。
final callRingbackEnabledProvider = NotifierProvider<_EnabledNotifier, bool>(
  () => _EnabledNotifier(initialCallRingbackEnabledProvider, _ringbackPrefsKey),
);
