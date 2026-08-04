import 'package:daidai/theme/gekiga/gekiga_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jitteredEdgePoints', () {
    test('同じseed・同じ長さなら、fromの平行移動だけ結果も平行移動する'
        '（隣接する箱の接する辺を同じ折れ線として共有できることの根拠）', () {
      const seed = 12345;
      final a = jitteredEdgePoints(
        const Offset(0, 0),
        const Offset(100, 0),
        seed,
        jitter: 2.4,
        segments: 5,
      );
      final shift = const Offset(0, 48);
      final b = jitteredEdgePoints(
        const Offset(0, 0) + shift,
        const Offset(100, 0) + shift,
        seed,
        jitter: 2.4,
        segments: 5,
      );

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        // 浮動小数点の丸め誤差を許容する（数学的には完全一致するはずの量）。
        expect((b[i] - (a[i] + shift)).distance, lessThan(1e-9));
      }
    });

    test('seedが違えば結果も異なる（独立したジグザグになる）', () {
      final a = jitteredEdgePoints(
        const Offset(0, 0),
        const Offset(100, 0),
        1,
        segments: 5,
      );
      final b = jitteredEdgePoints(
        const Offset(0, 0),
        const Offset(100, 0),
        2,
        segments: 5,
      );
      expect(a, isNot(equals(b)));
    });

    test('segments個の点を返し、常にtoに近い点で終わる', () {
      final points = jitteredEdgePoints(
        const Offset(0, 0),
        const Offset(10, 0),
        1,
        jitter: 1,
        segments: 7,
      );
      expect(points.length, 7);
      expect((points.last - const Offset(10, 0)).distance, lessThan(2));
    });
  });

  group('handDrawnPolygonPath', () {
    test('リファクタ後も閉じた有効なPathを返す（既存呼び出し元への回帰確認）', () {
      final path = handDrawnPolygonPath(
        [
          Offset.zero,
          const Offset(80, 0),
          const Offset(80, 40),
          const Offset(0, 40),
        ],
        7,
        jitter: 2.4,
        segmentsPerEdge: 5,
      );
      expect(path.computeMetrics().isNotEmpty, isTrue);
    });

    test('同じseedなら常に同じ形になる', () {
      final vertices = [
        Offset.zero,
        const Offset(80, 0),
        const Offset(80, 40),
        const Offset(0, 40),
      ];
      final pathA = handDrawnPolygonPath(vertices, 42);
      final pathB = handDrawnPolygonPath(vertices, 42);
      final metricsA = pathA.computeMetrics().toList();
      final metricsB = pathB.computeMetrics().toList();
      expect(metricsA.length, metricsB.length);
      for (var i = 0; i < metricsA.length; i++) {
        expect(metricsA[i].length, metricsB[i].length);
      }
    });
  });
}
