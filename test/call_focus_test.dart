import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/call_focus_provider.dart';

void main() {
  test('拡大しているタイルを覚え、解除するとグリッド（null）に戻る', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(callFocusedTileProvider, (_, _) {});
    addTearDown(sub.close);
    expect(container.read(callFocusedTileProvider), isNull);
    container.read(callFocusedTileProvider.notifier).focus('u1#screen');
    expect(container.read(callFocusedTileProvider), 'u1#screen');
    container.read(callFocusedTileProvider.notifier).clear();
    expect(container.read(callFocusedTileProvider), isNull);
  });

  test('見ている所が無くなる（通話画面を閉じる）と、拡大は解除される', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(callFocusedTileProvider, (_, _) {});
    container.read(callFocusedTileProvider.notifier).focus('self');
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(callFocusedTileProvider), isNull);
  });
}
