import 'package:daidai/models/nav_chip_layout.dart';
import 'package:daidai/providers/nav_chip_layout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _persistence();
  test('保存済みの並びに無い横丁は、末尾へ補われる', () {
    final order = normalizeNavChipOrder(['settings', 'talk', 'profile']);
    expect(order.last, HomeTabId.yokocho);
    expect(order.toSet(), HomeTabId.values.toSet());
  });

  test('横丁は、出す環境でだけ並ぶ', () {
    const order = NavChipLayout.standard;
    final hidden = visibleNavChipIndexes(order.order, showAccount: false);
    expect(hidden, isNot(contains(HomeTabId.yokocho.index)));
    final shown = visibleNavChipIndexes(
      order.order,
      showAccount: false,
      showYokocho: true,
    );
    expect(shown, contains(HomeTabId.yokocho.index));
  });
}

void _persistence() {
  test('「横丁」チップの表示設定は端末ごとに保存され、未保存の端末は表示する', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await loadInitialNavChipLayout()).yokochoChipEnabled, isTrue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(navChipLayoutProvider.notifier)
        .setYokochoChipEnabled(false);
    expect(container.read(navChipLayoutProvider).yokochoChipEnabled, isFalse);
    expect((await loadInitialNavChipLayout()).yokochoChipEnabled, isFalse);
  });
}
