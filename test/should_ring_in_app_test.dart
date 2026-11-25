import 'package:daidai/features/call/audio_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.rhing.daidai/call_action');

  void mock({required bool dnd, required bool access}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isDndActive') return dnd;
          if (call.method == 'hasDndAccess') return access;
          return null;
        });
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('おやすみモードでなければ、鳴らす', () async {
    mock(dnd: false, access: false);
    expect(await shouldRingInApp(urgent: false), true);
  });

  test('おやすみモード中の通常の発信は、鳴らさない', () async {
    mock(dnd: true, access: true);
    expect(await shouldRingInApp(urgent: false), false);
  });

  test('おやすみモード中の緊急の発信は、許可があれば鳴らし、無ければ鳴らさない', () async {
    mock(dnd: true, access: true);
    expect(await shouldRingInApp(urgent: true), true);
    mock(dnd: true, access: false);
    expect(await shouldRingInApp(urgent: true), false);
  });
}
