import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/providers/call_sound_enabled_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('既定は着信音・呼出音ともオン', () async {
    expect(await loadInitialCallRingtoneEnabled(), isTrue);
    expect(await loadInitialCallRingbackEnabled(), isTrue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(callRingtoneEnabledProvider), isTrue);
    expect(container.read(callRingbackEnabledProvider), isTrue);
  });

  test('オフにすると端末に保存され、次回の読み込みでもオフ（Webでも同じ）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(callRingtoneEnabledProvider.notifier).set(false);
    await container.read(callRingbackEnabledProvider.notifier).set(false);
    expect(container.read(callRingtoneEnabledProvider), isFalse);
    expect(await loadInitialCallRingtoneEnabled(), isFalse);
    expect(await loadInitialCallRingbackEnabled(), isFalse);
  });
}
