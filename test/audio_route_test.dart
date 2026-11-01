import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/audio_route.dart';

void main() {
  test('Bluetooth・有線は外部、内蔵は外部ではない', () {
    expect(isExternalAudioOutputLabel('Bluetooth'), isTrue);
    expect(isExternalAudioOutputLabel('Wired Headset'), isTrue);
    expect(isExternalAudioOutputLabel('AirPods Pro'), isTrue);
    expect(isExternalAudioOutputLabel('Speakerphone'), isFalse);
    expect(isExternalAudioOutputLabel('Earpiece'), isFalse);
    expect(isExternalAudioOutputLabel(''), isFalse);
  });
}
