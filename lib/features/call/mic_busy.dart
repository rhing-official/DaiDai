import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('jp.rhing.daidai/pip');

/// 今、他のアプリがマイクを使っているか（Androidのみ。通話に入る前の注意に使う、2026-11-16）。
/// 自分の録音を始める前に呼ぶ。分からない・Android以外は`false`。
Future<bool> isMicBusyNow() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _channel.invokeMethod<bool>('isMicBusy') ?? false;
  } catch (_) {
    return false;
  }
}
