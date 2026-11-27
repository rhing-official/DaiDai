import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/chat_edge_fade.dart';

void main() {
  haloTests();
  group('ChatEdgeFade.buildMask', () {
    test('上端は透明、フェード後は不透明、下端で透明になる', () {
      final m = ChatEdgeFade.buildMask(
        height: 600,
        topClear: 100,
        topFade: 32,
        bottomFade: 80,
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
      final m = ChatEdgeFade.buildMask(
        height: 600,
        topClear: 100,
        topFade: 0,
        bottomFade: 0,
      );
      expect(m.alphas.last, 1);
      final i = m.stops.lastIndexWhere((t) => (t - 100 / 600).abs() < 1e-9);
      expect(m.alphas[i], 1);
    });

    test('高さが無くても壊れない', () {
      final m = ChatEdgeFade.buildMask(
        height: 0,
        topClear: 100,
        topFade: 32,
        bottomFade: 80,
      );
      expect(m.stops, [0.0, 1.0]);
    });

    test('上下のフェードが重なっても、位置は単調に増える', () {
      final m = ChatEdgeFade.buildMask(
        height: 100,
        topClear: 40,
        topFade: 32,
        bottomFade: 90,
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

void haloTests() {
  test('入力欄の矩形は、余白の内側を滲みの分だけ広げる', () {
    final r = haloRect(
      size: const Size(400, 600),
      boxTopFromBottom: 100,
      insets: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    );
    const g = ChatEdgeFade.haloSigma;
    expect(r.left, 12 - g);
    expect(r.right, 400 - 12 + g);
    expect(r.top, 500 - g);
    expect(r.bottom, 588 + g);
  });
}
