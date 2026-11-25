import 'package:daidai/features/call/audio_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('受話口で、手動で選んでいなければ、自動でスピーカーにする', () {
    expect(shouldAutoSpeaker(speakerOn: false, manuallySet: false), true);
  });

  test('既にスピーカーなら、何もしない', () {
    expect(shouldAutoSpeaker(speakerOn: true, manuallySet: false), false);
    expect(shouldAutoSpeaker(speakerOn: true, manuallySet: true), false);
  });

  test('手動で受話口を選んだ後は、自動で切り替えない', () {
    expect(shouldAutoSpeaker(speakerOn: false, manuallySet: true), false);
  });
}
