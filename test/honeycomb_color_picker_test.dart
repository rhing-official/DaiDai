import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/honeycomb_color_picker.dart';

void main() {
  test('127マス＋グレー7マス、座標の重複なし、中央は白', () {
    final cells = honeycombCells();
    final honey = cells.where((c) => !c.gray).toList();
    expect(honey.length, 127);
    expect(cells.where((c) => c.gray).length, 7);
    expect({for (final c in cells) '${c.q},${c.r}'}.length, cells.length);
    expect(
      honey.firstWhere((c) => c.q == 0 && c.r == 0).color,
      const Color(0xFFFFFFFF),
    );
  });

  testWidgets('マスを選んで完了で色を返す／外側は何も返さない', (tester) async {
    Color? result;
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showHoneycombColorDialog(context);
              called = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('honeycomb-0-0')));
    await tester.pumpAndSettle();
    // タップしただけでは閉じない。
    expect(called, isFalse);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(result, const Color(0xFFFFFFFF));

    called = false;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(result, isNull);
  });

  testWidgets('押したまま滑らせると、乗った丸を順に選ぶ', (tester) async {
    final picked = <Color>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: HoneycombColorPicker(onPicked: picked.add)),
        ),
      ),
    );
    final from = tester.getCenter(find.byKey(const ValueKey('honeycomb-0-0')));
    final to = tester.getCenter(find.byKey(const ValueKey('honeycomb-3-0')));
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(to);
    await gesture.up();
    expect(picked.first, const Color(0xFFFFFFFF));
    expect(picked.last, isNot(const Color(0xFFFFFFFF)));
    expect(picked.length, greaterThan(1));
  });
}
