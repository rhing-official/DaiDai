import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/providers/locked_call_providers.dart';

void main() {
  test('ロック中モードは既定false、setで切り替わる', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(lockedCallModeProvider), isFalse);
    container.read(lockedCallModeProvider.notifier).set(true);
    expect(container.read(lockedCallModeProvider), isTrue);
  });

  test('戻るの認証成功の通知は回数が増える', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(lockedBackUnlockedProvider), 0);
    container.read(lockedBackUnlockedProvider.notifier).bump();
    expect(container.read(lockedBackUnlockedProvider), 1);
  });

  test('Android以外では端末の認証は常に成功扱い', () async {
    expect(await requestDeviceUnlock(), isTrue);
  });
}
