import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Web以外では、送る音の音量を変えられない（トラックのゲインを変えるAPIが無い）。
class SendGain {
  SendGain._();

  static bool get isSupported => false;

  /// 何もせずnullを返す（元のトラックのまま送る）。
  static Future<SendGain?> attach(MediaStreamTrack source) async => null;

  /// 処理後のトラック（この環境では使わない）。
  MediaStreamTrack get track => throw UnsupportedError('SendGain');

  void setGain(double gain) {}

  Future<void> dispose() async {}
}
