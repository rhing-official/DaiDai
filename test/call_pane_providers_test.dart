import 'package:daidai/providers/chat_navigation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 通話UIの表示状態（2026-10-11）。ミニ表示は「通話UIが実際に出ている間だけ」隠れる。
void main() {
  test('通話UIの表示報告は、その会話の時だけ下ろせる', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(embeddedCallShownProvider.notifier);

    notifier.set(const ViewedDm('d1'));
    expect(container.read(embeddedCallShownProvider), const ViewedDm('d1'));

    // 別の会話の後始末では下ろさない（切り替え直後の競合対策）。
    notifier.clearIfCurrent(const ViewedDm('d2'));
    expect(container.read(embeddedCallShownProvider), const ViewedDm('d1'));

    notifier.clearIfCurrent(const ViewedDm('d1'));
    expect(container.read(embeddedCallShownProvider), isNull);
  });

  test('通話UIへ戻る要求は、同じ会話への連続要求も変化として通知される', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <(ViewedConversation, int)?>[];
    container.listen(callPaneRequestProvider, (_, next) => seen.add(next));

    final notifier = container.read(callPaneRequestProvider.notifier);
    notifier.request(const ViewedDm('d1'));
    notifier.request(const ViewedDm('d1'));

    expect(seen.length, 2);
    expect(seen.first!.$1, const ViewedDm('d1'));
    expect(seen.last!.$2, greaterThan(seen.first!.$2));
  });
}
