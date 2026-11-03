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
  void stop() {}
  set volume(double value) {}
  void dispose() {}
}
