import 'package:daidai/widgets/water_columns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('片側から水を入れると、反対側へ広がり、量は入れた分だけ', () {
    final w = WaterColumns();
    for (var i = 0; i < 8; i++) {
      w.add(0.1, 0.75);
      w.step(1 / 60);
    }
    expect(w.total, closeTo(6, 1e-6));
    // 入れた側が深い。
    expect(w.depthAt(0.1), greaterThan(w.depthAt(0.9)));
  });

  test('水は、流れて広がり、やがて平らに収まり、量は保たれる', () {
    final w = WaterColumns();
    w.add(0.05, 12, spread: 1.2);
    final before = w.total;
    for (var i = 0; i < 60 * 6; i++) {
      w.step(1 / 60);
    }
    expect(w.total, closeTo(before, 1e-6));
    expect(w.activity, lessThan(0.2));
    expect((w.depthAt(0.05) - w.depthAt(0.95)).abs(), lessThan(0.1));
  });

  test('水を抜くと、抜いた量だけ減る（足りなければあるだけ）', () {
    final w = WaterColumns()..fillInstantly();
    final removed = w.remove(0.9, 6);
    expect(removed, closeTo(6, 1e-6));
    expect(w.total, closeTo(18, 1e-6));
    expect(w.remove(0.5, 100), closeTo(18, 1e-6));
    expect(w.total, closeTo(0, 1e-6));
  });

  test('水深は、負にならず、上限を超えない', () {
    final w = WaterColumns();
    w.add(0.5, 30);
    w.impulse(0.5, 3);
    for (var i = 0; i < 300; i++) {
      w.step(1 / 30);
    }
    expect(
      w.depths.every((d) => d >= 0 && d <= WaterColumns.maxDepth + 1e-6),
      isTrue,
    );
  });

  test('満水で収まると、isFullになる', () {
    final w = WaterColumns()..fillInstantly();
    expect(w.isFull, isTrue);
    expect(w.isEmpty, isFalse);
    w.remove(0.5, 100);
    expect(w.isEmpty, isTrue);
  });
}
