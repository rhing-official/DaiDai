import 'package:daidai/widgets/viewer_nav_arrows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('先頭は左を、末尾は右を隠し、1件だけなら両方隠す', () {
    expect(ViewerNavArrows.showsPrevious(0, 5), isFalse);
    expect(ViewerNavArrows.showsNext(0, 5), isTrue);
    expect(ViewerNavArrows.showsPrevious(2, 5), isTrue);
    expect(ViewerNavArrows.showsNext(2, 5), isTrue);
    expect(ViewerNavArrows.showsPrevious(4, 5), isTrue);
    expect(ViewerNavArrows.showsNext(4, 5), isFalse);
    expect(ViewerNavArrows.showsPrevious(0, 1), isFalse);
    expect(ViewerNavArrows.showsNext(0, 1), isFalse);
  });

  testWidgets('visibleがfalseの間は透明で、押せない', (tester) async {
    var next = 0;
    Future<void> pump(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerNavArrows(
            visible: visible,
            index: 1,
            count: 3,
            onPrevious: () {},
            onNext: () => next++,
          ),
        ),
      ),
    );

    await pump(true);
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(next, 1);

    await pump(false);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.tap(find.byIcon(Icons.chevron_right), warnIfMissed: false);
    expect(next, 1);
  });
}
