import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/features/call/webrtc_media_constraints.dart';
import 'package:daidai/providers/mic_denoise_provider.dart';

void main() {
  group('マイクのノイズ除去（RNNoise）', () {
    test('RNNoiseを使う時は、標準のノイズ抑制を切る（二重にかけない）', () {
      // テストの既定のプラットフォームはAndroid（単純な`true`指定）なので、デスクトップ扱いにする。
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final on = buildAudioConstraints(rnnoise: true) as Map;
      expect(on['noiseSuppression'], isFalse);
      expect(on['googNoiseSuppression'], isFalse);
      expect(on['echoCancellation'], isTrue);
      final off = buildAudioConstraints() as Map;
      expect(off['noiseSuppression'], isTrue);
    });

    test('設定の既定はオンで、保存した値を読み戻せる', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadMicDenoiseEnabled(), isTrue);
      SharedPreferences.setMockInitialValues({'micDenoiseEnabled': false});
      expect(await loadMicDenoiseEnabled(), isFalse);
    });

    test('Web以外では、ノイズ除去を使わない（生のトラックのまま）', () async {
      expect(await shouldDenoiseMic(), isFalse);
      expect(await applyMicDenoise(null, true), isNull);
    });
  });
}
