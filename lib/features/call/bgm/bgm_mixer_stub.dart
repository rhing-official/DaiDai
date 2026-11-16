import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Web以外では未対応（ボタンを出さない）。
class BgmMixer {
  static bool get isSupported => false;

  MediaStreamTrack attach(MediaStreamTrack mic) => mic;
  Future<void> play(
    Uint8List bytes,
    String mimeType, {
    void Function()? onEnded,
  }) async {}
  Future<void> stop({bool fade = true}) async {}
  Duration get position => Duration.zero;
  Duration? get duration => null;
  void seek(Duration to) {}
  bool get paused => true;
  Future<void> pause() async {}
  Future<void> resume() async {}
  set volume(double value) {}
  set effectVolume(double value) {}
  Future<void> playEffect(
    String key,
    Uint8List bytes, {
    void Function()? onEnded,
  }) async {}
  void dispose() {}
}
