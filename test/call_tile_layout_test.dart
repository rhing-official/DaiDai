import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _grid(Size size, int count) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: CallTileGrid(
        tiles: [
          for (var i = 0; i < count; i++)
            ColoredBox(key: ValueKey('t$i'), color: Colors.grey),
        ],
      ),
    ),
  ),
);

void main() {
  group('callTileRowSizes', () {
    test('縦長: 2人=縦2段、3人=上1下2、4人=2×2、奇数は上の行が1人', () {
      expect(callTileRowSizes(1, portrait: true), [1]);
      expect(callTileRowSizes(2, portrait: true), [1, 1]);
      expect(callTileRowSizes(3, portrait: true), [1, 2]);
      expect(callTileRowSizes(4, portrait: true), [2, 2]);
      expect(callTileRowSizes(5, portrait: true), [1, 2, 2]);
      expect(callTileRowSizes(6, portrait: true), [2, 2, 2]);
    });

    test('横長・0人は従来のグリッド（null）', () {
      expect(callTileRowSizes(3, portrait: false), isNull);
      expect(callTileRowSizes(0, portrait: true), isNull);
    });
  });

  group('CallTileGrid', () {
    testWidgets('縦長の2人は縦に並ぶ', (tester) async {
      await tester.pumpWidget(_grid(const Size(300, 600), 2));
      final a = tester.getRect(find.byKey(const ValueKey('t0')));
      final b = tester.getRect(find.byKey(const ValueKey('t1')));
      expect(a.left, b.left);
      expect(a.bottom, lessThan(b.top));
    });

    testWidgets('縦長の3人は上に1人（全幅）、下に2人', (tester) async {
      await tester.pumpWidget(_grid(const Size(300, 600), 3));
      final a = tester.getRect(find.byKey(const ValueKey('t0')));
      final b = tester.getRect(find.byKey(const ValueKey('t1')));
      final c = tester.getRect(find.byKey(const ValueKey('t2')));
      expect(a.width, greaterThan(b.width * 1.5));
      expect(b.top, c.top);
      expect(b.right, lessThan(c.left));
      expect(a.bottom, lessThan(b.top));
    });

    testWidgets('縦長の4人は上下2人ずつ', (tester) async {
      await tester.pumpWidget(_grid(const Size(300, 600), 4));
      final r = [
        for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey('t$i'))),
      ];
      expect(r[0].top, r[1].top);
      expect(r[2].top, r[3].top);
      expect(r[0].bottom, lessThan(r[2].top));
    });

    testWidgets('横長は従来どおりのグリッド（2人は横に並ぶ）', (tester) async {
      await tester.pumpWidget(_grid(const Size(600, 300), 2));
      final a = tester.getRect(find.byKey(const ValueKey('t0')));
      final b = tester.getRect(find.byKey(const ValueKey('t1')));
      expect(a.top, b.top);
      expect(a.right, lessThan(b.left));
    });
  });
}
