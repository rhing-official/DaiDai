import 'package:daidai/providers/call_display_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('PiPに入ってよいか: 方針と映像の有無で決まる', () {
    expect(callPipAllowed(CallPipPolicy.video, hasVideo: false), isFalse);
    expect(callPipAllowed(CallPipPolicy.video, hasVideo: true), isTrue);
    expect(callPipAllowed(CallPipPolicy.always, hasVideo: false), isTrue);
    expect(callPipAllowed(CallPipPolicy.never, hasVideo: true), isFalse);
  });

  test('保存した値を読み戻し、未保存・不明な値は既定になる', () async {
    SharedPreferences.setMockInitialValues({
      'callMiniStyle': 'none',
      'callPipPolicy': 'always',
    });
    expect(await loadInitialCallMiniStyle(), CallMiniStyle.none);
    expect(await loadInitialCallPipPolicy(), CallPipPolicy.always);
    SharedPreferences.setMockInitialValues({'callMiniStyle': 'zzz'});
    expect(await loadInitialCallMiniStyle(), CallMiniStyle.platformDefault);
    expect(await loadInitialCallPipPolicy(), CallPipPolicy.video);
  });
}
