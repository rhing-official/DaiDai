import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ScrollController> pump(WidgetTester tester, bool enabled) async {
    final outer = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: outer,
          children: [
            SizedBox(
              height: 100,
              child: WheelScrollAbsorber(
                enabled: enabled,
                child: const SingleChildScrollView(
                  child: SizedBox(height: 300, width: 300),
                ),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    return outer;
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(50, 50)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('内側が末尾に達しても、外側の一覧は動かない', (tester) async {
    final outer = await pump(tester, true);
    await wheel(tester, 500); // 内側の末尾まで
    await wheel(tester, 200); // 端に達した後
    expect(outer.offset, 0);
  });

  testWidgets('無効のときは、端で外側の一覧へ渡る', (tester) async {
    final outer = await pump(tester, false);
    await wheel(tester, 500);
    await wheel(tester, 200);
    expect(outer.offset, greaterThan(0));
  });
}
