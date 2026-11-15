import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Web以外ではノイズ除去（RNNoise）を使えない。
class MicDenoiser {
  MicDenoiser._();

  static bool get isSupported => false;

  /// 何もせずnullを返す（生のトラックのまま使う）。
  static Future<MicDenoiser?> attach(MediaStream stream) async => null;

  Future<void> dispose() async {}
}
