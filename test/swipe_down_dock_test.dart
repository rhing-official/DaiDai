import 'package:daidai/features/call/swipe_down_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int> pump(WidgetTester tester, Offset from, Offset delta) async {
    var docked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeDownDock(
          onDock: () => docked++,
          // 子が縦ドラッグ・タップを奪っても、ドックの判定は働く。
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onVerticalDragUpdate: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.dragFrom(from, delta);
    await tester.pump();
    return docked;
  }

  testWidgets('真下に60px以上動かすとドックする', (tester) async {
    expect(await pump(tester, const Offset(200, 100), const Offset(0, 120)), 1);
  });

  testWidgets('短い動きや横向きの動きではドックしない', (tester) async {
    expect(await pump(tester, const Offset(200, 100), const Offset(0, 30)), 0);
    expect(
      await pump(tester, const Offset(200, 100), const Offset(150, 100)),
      0,
    );
  });

  testWidgets('上向きの動きではドックしない', (tester) async {
    expect(
      await pump(tester, const Offset(200, 300), const Offset(0, -120)),
      0,
    );
  });

  testWidgets('下端の操作ボタン列から始めた動きは数えない', (tester) async {
    // テストの画面は高さ600。下から160px以内は対象外。
    expect(await pump(tester, const Offset(200, 500), const Offset(0, 80)), 0);
  });
}
