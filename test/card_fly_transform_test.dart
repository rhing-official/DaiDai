import 'package:daidai/features/profile/profile_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = Rect.fromLTWH(0, 0, 200, 250);
  const target = Rect.fromLTWH(300, 100, 400, 500);

  test('t=0で一覧の位置・大きさ、t=1で最終位置になる', () {
    final m0 = cardFlyTransform(origin, target, 0);
    // 最終位置の中心を基準にした変換なので、中心は一覧の中心へ動き、幅は半分になる。
    expect(m0.storage[0], closeTo(0.5, 1e-9));
    expect(
      m0.getTranslation().x,
      closeTo(origin.center.dx - target.center.dx, 1e-9),
    );
    expect(
      m0.getTranslation().y,
      closeTo(origin.center.dy - target.center.dy, 1e-9),
    );

    final m1 = cardFlyTransform(origin, target, 1);
    expect(m1.storage[0], closeTo(1, 1e-9));
    expect(m1.getTranslation().x, closeTo(0, 1e-9));
    expect(m1.getTranslation().y, closeTo(0, 1e-9));
  });
}
