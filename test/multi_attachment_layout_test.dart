import 'package:daidai/utils/multi_attachment_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 複数添付グリッドの配置: 全体が欠けのない正方形・長方形になること。
void main() {
  const width = 280.0;
  const gap = 2.0;

  for (var n = 1; n <= 10; n++) {
    test('$n枚: タイルは枠内に収まり、重ならず、すきま以外を埋める', () {
      final layout = multiAttachmentLayout(n, width, gap: gap);
      expect(layout.tiles.length, n);
      for (final tile in layout.tiles) {
        expect(tile.left, greaterThanOrEqualTo(-1e-9));
        expect(tile.top, greaterThanOrEqualTo(-1e-9));
        expect(tile.right, lessThanOrEqualTo(width + 1e-9));
        expect(tile.bottom, lessThanOrEqualTo(layout.height + 1e-9));
      }
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final overlap = layout.tiles[i]
              .deflate(0.01)
              .overlaps(layout.tiles[j].deflate(0.01));
          expect(overlap, isFalse, reason: '$i と $j が重なっている');
        }
      }
      // 全体は幅いっぱい（右端と下端にタイルが届く）。
      expect(
        layout.tiles.map((t) => t.right).reduce((a, b) => a > b ? a : b),
        closeTo(width, 1e-6),
      );
      expect(
        layout.tiles.map((t) => t.bottom).reduce((a, b) => a > b ? a : b),
        closeTo(layout.height, 1e-6),
      );
    });
  }

  test('10枚は1枚目が全幅、残り9枚が3列×3行', () {
    final layout = multiAttachmentLayout(10, width, gap: gap);
    expect(layout.tiles.first.width, width);
    final rest = layout.tiles.skip(1).toList();
    expect(rest.map((t) => t.left).toSet().length, 3);
    expect(rest.map((t) => t.top).toSet().length, 3);
  });

  test('3枚は左の1枚が右2枚の高さ全体を占める', () {
    final layout = multiAttachmentLayout(3, width, gap: gap);
    final left = layout.tiles[0];
    expect(left.height, closeTo(layout.tiles[2].bottom, 1e-9));
    expect(layout.tiles[1].top, 0);
    expect(layout.tiles[2].left, layout.tiles[1].left);
  });

  test('4・6・9枚は正方形のタイルだけで並ぶ', () {
    for (final n in [4, 6, 9]) {
      for (final t in multiAttachmentLayout(n, width, gap: gap).tiles) {
        expect(t.width, closeTo(t.height, 1e-9));
      }
    }
  });
}
