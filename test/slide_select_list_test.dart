import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/widgets/slide_select_list.dart';

Future<List<int>> _pump(WidgetTester tester) async {
  final ended = <int>[];
  await tester.pumpWidget(
    MaterialApp(
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
}
