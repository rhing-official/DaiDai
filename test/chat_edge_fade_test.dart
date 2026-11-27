import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/chat_edge_fade.dart';

void main() {
  group('ChatEdgeFade.buildMask', () {
    test('上端は透明、フェード後は不透明、下端で透明になる', () {
      final m = ChatEdgeFade.buildMask(
        height: 600,
        topClear: 100,
        topFade: 32,
        boxTopFromBottom: 80,
      );
      expect(m.alphas.first, 0);
      expect(m.alphas.last, 0);
      expect(m.stops.first, 0);
      expect(m.stops.last, 1);
      // 上の透明範囲の終わり（100/600）まで0。
      final iClear = m.stops.indexWhere((t) => t > 100 / 600 + 1e-9);
      expect(m.alphas[iClear - 1], 0);
      // 中ほどは完全に不透明。
      final iMid = m.stops.indexWhere((t) => t >= 300 / 600);
      expect(m.alphas[iMid], 1);
      // 位置は単調に増える。
      for (var i = 1; i < m.stops.length; i++) {
        expect(m.stops[i], greaterThanOrEqualTo(m.stops[i - 1]));
      }
    });

    test('端に着いた時（フェード幅0）は、透明範囲の直後から不透明', () {
      final m = ChatEdgeFade.buildMask(height: 600, topClear: 100, topFade: 0);
      expect(m.alphas.last, 1);
      final i = m.stops.lastIndexWhere((t) => (t - 100 / 600).abs() < 1e-9);
      expect(m.alphas[i], 1);
    });

    test('入力欄の上端で透明になり、そこから下は下端まで透明のまま', () {
      final m = ChatEdgeFade.buildMask(
        height: 600,
        topClear: 0,
        topFade: 0,
        boxTopFromBottom: 100,
        boxFade: 24,
      );
      double alphaAt(double y) {
        final t = y / 600;
        for (var i = 1; i < m.stops.length; i++) {
          if (t <= m.stops[i]) {
            final span = m.stops[i] - m.stops[i - 1];
            if (span == 0) return m.alphas[i];
            final u = (t - m.stops[i - 1]) / span;
            return m.alphas[i - 1] + (m.alphas[i] - m.alphas[i - 1]) * u;
          }
        }
        return m.alphas.last;
      }

      expect(alphaAt(400), closeTo(1, 1e-6)); // 滲みの手前（上端の24px上）
      expect(alphaAt(500), closeTo(0, 1e-6)); // 入力欄の上端
      expect(alphaAt(550), 0); // 箱の左右・下の余白の高さ
      expect(alphaAt(600), 0); // 一覧の下端
    });

    test('高さが無くても壊れない', () {
      final m = ChatEdgeFade.buildMask(
        height: 0,
        topClear: 100,
        topFade: 32,
        boxTopFromBottom: 80,
      );
      expect(m.stops, [0.0, 1.0]);
    });

    test('上下のフェードが重なっても、位置は単調に増える', () {
      final m = ChatEdgeFade.buildMask(
        height: 100,
        topClear: 40,
        topFade: 32,
        boxTopFromBottom: 90,
      );
      for (var i = 1; i < m.stops.length; i++) {
        expect(m.stops[i], greaterThanOrEqualTo(m.stops[i - 1]));
      }
    });
  });

  test('topStrength は止まっている時0、24px動くと1', () {
    expect(ChatEdgeFade.topStrength(0), 0);
    expect(ChatEdgeFade.topStrength(-5), 0);
    expect(ChatEdgeFade.topStrength(12), 0.5);
    expect(ChatEdgeFade.topStrength(100), 1);
  });
}
