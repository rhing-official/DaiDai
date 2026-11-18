import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 端末がロックされたままの通話中か（2026-11-18、Android）。trueの間、通話画面から出る操作
/// （下スワイプ・戻る・Esc）は、先に端末の認証（生体認証など）を求める。
/// `LockScreenCallGuard`が更新する。
class LockedCallModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final lockedCallModeProvider = NotifierProvider<LockedCallModeNotifier, bool>(
  LockedCallModeNotifier.new,
);

/// ロック中に戻るボタンを押し、端末の認証に成功した回数（ネイティブからの通知）。通話画面が
/// 受けて、通常の戻る操作（OSのPiP・ミニ表示）を行う。
class LockedBackUnlockedNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final lockedBackUnlockedProvider =
    NotifierProvider<LockedBackUnlockedNotifier, int>(
      LockedBackUnlockedNotifier.new,
    );

const _channel = MethodChannel('jp.rhing.daidai/call_action');

/// 端末の認証画面（生体認証・PIN・パターン）を出す。成功したらtrue。Android以外は常にtrue。
Future<bool> requestDeviceUnlock() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  try {
    return await _channel.invokeMethod<bool>('requestUnlock') ?? false;
  } on MissingPluginException {
    return true;
  } on PlatformException {
    return false;
  }
}
