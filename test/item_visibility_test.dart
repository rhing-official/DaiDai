import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/utils/item_visibility.dart';

void main() {
  bool visible(double lead, double trail) => isItemFullyVisible(
    leadingEdge: lead,
    trailingEdge: trail,
    viewportHeight: 1000,
    bottomInset: 100,
    topInset: 100,
  );

  test('隠れる領域を除いた範囲に収まっていれば見えている', () {
    expect(visible(0.3, 0.4), isTrue);
    expect(visible(0.1, 0.9), isTrue);
  });
  test('入力欄の裏にかかっていれば見えていない', () {
    expect(visible(0.05, 0.2), isFalse);
  });
  test('上部バーの裏にかかっていれば見えていない', () {
    expect(visible(0.8, 0.95), isFalse);
  });
  test('画面外なら見えていない', () {
    expect(visible(1.2, 1.3), isFalse);
    expect(visible(-0.3, -0.1), isFalse);
  });
  test('ビューポートが0なら見えていない', () {
    expect(
      isItemFullyVisible(
        leadingEdge: 0,
        trailingEdge: 1,
        viewportHeight: 0,
        bottomInset: 0,
        topInset: 0,
      ),
      isFalse,
    );
  });
}
