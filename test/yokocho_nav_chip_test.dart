import 'package:daidai/models/nav_chip_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
