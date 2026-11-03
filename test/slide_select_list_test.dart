import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/providers/home_shell_providers.dart';
import 'package:daidai/widgets/slide_select_list.dart';

Future<List<int>> _pump(WidgetTester tester) async {
  final ended = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SlideSelectList(
            itemCount: 5,
            onSlideEnd: ended.add,
            builder: (context, keyFor, slidingIndex) => Column(
              children: [
                for (var i = 0; i < 5; i++)
                  SizedBox(key: keyFor(i), height: 60, child: Text('item $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return ended;
}

void main() {
  testWidgets('縦になぞって離すと、最後にいた項目が選ばれる', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 120));
    await gesture.up();
    expect(ended, [3]);
  });

  testWidgets('縦に少し動いてから大きく横へ動いて離しても、選ばれない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(0, 14));
    await gesture.moveBy(const Offset(120, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('横だけ動かして離しても、選ばれない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(60, 3));
    await gesture.moveBy(const Offset(60, 20));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('ほとんど動かさずに離した時は、なぞりとして扱わない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(2, 4));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('チップ列から滑ってきた指（橋渡し）で項目を選べて、外では何も起きない', (tester) async {
    final ended = await _pump(tester);
    final bridge = ProviderScope.containerOf(
      tester.element(find.byType(SlideSelectList)),
    ).read(itemPickBridgeProvider);

    // 一覧の上: 項目2（y=120〜180）。
    final target = bridge.targetAt(const Offset(20, 130));
    expect(target, isNotNull);
    expect(target!.indexAt(const Offset(20, 130)), 2);
    target.pick(2, commit: false);
    await tester.pump();
    target.pick(2, commit: true);
    expect(ended, [2]);

    // 一覧の外（画面の外）は対象にならない。
    expect(bridge.targetAt(const Offset(20, 5000)), isNull);
  });
}
