import 'package:daidai/features/call/call_pin_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ピンの切替・全解除・存在しないキーの除去', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(callPinnedTilesProvider, (_, _) {});
    addTearDown(sub.close);
    final n = container.read(callPinnedTilesProvider.notifier);
    n.toggle('a');
    n.toggle('b#screen');
    expect(container.read(callPinnedTilesProvider), {'a', 'b#screen'});
    n.toggle('a');
    expect(container.read(callPinnedTilesProvider), {'b#screen'});
    n.retain({'a'});
    expect(container.read(callPinnedTilesProvider), isEmpty);
    n.toggle('a');
    n.clear();
    expect(container.read(callPinnedTilesProvider), isEmpty);
  });

  test('通話画面が無くなっても、ピンは残る（通話の間は保持）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(callPinnedTilesProvider, (_, _) {});
    container.read(callPinnedTilesProvider.notifier).toggle('self');
    sub.close();
    await container.pump();
    expect(container.read(callPinnedTilesProvider), {'self'});
  });
}
