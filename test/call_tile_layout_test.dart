import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:daidai/features/call/call_pin_provider.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _stage(Size size, List<String> keys, {ProviderContainer? container}) {
  final child = MaterialApp(
    home: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CallTileStage(
          specs: [
            for (final k in keys)
              CallTileSpec(
                key: k,
                build: (_) =>
                    ColoredBox(key: ValueKey('t$k'), color: Colors.grey),
              ),
          ],
        ),
      ),
    ),
  );
  return container == null
      ? ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: child,
        )
      : UncontrolledProviderScope(container: container, child: child);
}

Rect _r(WidgetTester t, String k) => t.getRect(find.byKey(ValueKey('t$k')));

void main() {
  group('callTileRowSizes', () {
    test('縦長: 1=[1]、2=縦2段、奇数は最上行が1枚', () {
      final expected = {
        1: [1],
        2: [1, 1],
        3: [1, 2],
        4: [2, 2],
        5: [1, 2, 2],
        6: [2, 2, 2],
        7: [1, 2, 2, 2],
      };
      expected.forEach((n, rows) {
        expect(callTileRowSizes(n, portrait: true), rows, reason: 'n=$n');
      });
    });

    test('横長: 2=横並べ、3=上1下2、4=2×2、5=上2下3、6=上下3、9以上は1行最大4', () {
      final expected = {
        1: [1],
        2: [2],
        3: [1, 2],
        4: [2, 2],
        5: [2, 3],
        6: [3, 3],
        7: [3, 4],
        8: [4, 4],
        9: [1, 4, 4],
        10: [2, 4, 4],
        11: [3, 4, 4],
        12: [4, 4, 4],
      };
      expected.forEach((n, rows) {
        expect(callTileRowSizes(n, portrait: false), rows, reason: 'n=$n');
      });
    });

    test('0枚はnull', () {
      expect(callTileRowSizes(0, portrait: true), isNull);
      expect(callTileRowSizes(0, portrait: false), isNull);
    });
  });

  group('CallTileStage', () {
    testWidgets('縦長の2枚は縦に並ぶ', (tester) async {
      await tester.pumpWidget(_stage(const Size(300, 600), ['a', 'b']));
      expect(_r(tester, 'a').left, _r(tester, 'b').left);
      expect(_r(tester, 'a').bottom, lessThan(_r(tester, 'b').top));
    });

    testWidgets('横長の2枚は横に並ぶ', (tester) async {
      await tester.pumpWidget(_stage(const Size(600, 300), ['a', 'b']));
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'a').right, lessThan(_r(tester, 'b').left));
    });

    testWidgets('横長の3枚は上1枚（下と同じ幅で中央）、下2枚', (tester) async {
      await tester.pumpWidget(_stage(const Size(600, 300), ['a', 'b', 'c']));
      final a = _r(tester, 'a');
      final b = _r(tester, 'b');
      final c = _r(tester, 'c');
      expect(a.width, closeTo(b.width, 0.5));
      expect(a.center.dx, closeTo(400, 0.5)); // 領域（600幅）の中央＝画面の中央
      expect(b.top, c.top);
      expect(a.bottom, lessThan(b.top));
    });

    testWidgets('横長の4枚は上下2枚ずつ、5枚は上2下3', (tester) async {
      await tester.pumpWidget(
        _stage(const Size(800, 400), ['a', 'b', 'c', 'd']),
      );
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'c').top, _r(tester, 'd').top);
      expect(_r(tester, 'a').bottom, lessThan(_r(tester, 'c').top));
      await tester.pumpWidget(
        _stage(const Size(900, 400), ['a', 'b', 'c', 'd', 'e']),
      );
      await tester.pump();
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'c').top, _r(tester, 'e').top);
      expect(_r(tester, 'b').bottom, lessThan(_r(tester, 'c').top));
    });

    testWidgets('縦長の5枚は上1枚（全幅）、その下に2枚ずつ', (tester) async {
      await tester.pumpWidget(
        _stage(const Size(300, 700), ['a', 'b', 'c', 'd', 'e']),
      );
      expect(_r(tester, 'a').width, greaterThan(_r(tester, 'b').width * 1.5));
      expect(_r(tester, 'b').top, _r(tester, 'c').top);
      expect(_r(tester, 'd').top, _r(tester, 'e').top);
    });

    testWidgets('ピン留めした枚は上の大きい部分、残りは下の帯に並ぶ', (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _stage(const Size(600, 400), ['a', 'b', 'c'], container: container),
      );
      await tester.tap(find.byKey(const ValueKey('pin-a')));
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), {'a'});
      final a = _r(tester, 'a');
      final b = _r(tester, 'b');
      final c = _r(tester, 'c');
      expect(a.height, greaterThan(b.height * 2));
      expect(b.top, c.top);
      expect(a.bottom, lessThanOrEqualTo(b.top));
    });

    testWidgets('もう一度押すとピンが外れ、消えたウィンドウのピンは外れる', (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _stage(const Size(600, 400), ['a', 'b'], container: container),
      );
      container.read(callPinnedTilesProvider.notifier).toggle('a');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pin-a')));
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), isEmpty);
      container.read(callPinnedTilesProvider.notifier).toggle('zzz');
      await tester.pump();
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), isEmpty);
    });

    testWidgets('音量のあるウィンドウにだけ音量ボタンが出て、スライダーで値が変わる', (tester) async {
      double? changed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 600,
              height: 400,
              child: CallTileStage(
                specs: [
                  CallTileSpec(
                    key: 'a',
                    volume: CallTileVolume(
                      value: 0.8,
                      onChanged: (v) => changed = v,
                    ),
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                  CallTileSpec(
                    key: 'b',
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('volume-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('volume-b')), findsNothing);
      expect(find.byKey(const ValueKey('volume-slider-a')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('volume-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsOneWidget);
      final slider = find.byKey(const ValueKey('volume-slider-a'));
      await tester.tap(slider);
      await tester.pump();
      expect(changed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('volume-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsNothing);
    });
  });
}
