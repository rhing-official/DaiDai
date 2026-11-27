import 'package:daidai/models/slide_transition_style.dart';
import 'package:daidai/theme/motion.dart';
import 'package:daidai/widgets/scribble_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => activeSlideTransitionStyle = SlideTransitionStyle.pop);

  test('描きは保存名から読め、薄くもスライドもしない', () {
    final style = SlideTransitionStyle.fromName('draw');
    expect(style, SlideTransitionStyle.draw);
    expect(style.usesDraw, isTrue);
    expect(style.usesFade, isFalse);
    expect(style.usesBlur, isFalse);
    expect(style.usesSlide, isFalse);
    expect(style.usesPopScale, isFalse);
  });

  testWidgets('描きのダイアログは、途中でも終わりでも例外なく、終わりで全て見える', (tester) async {
    activeSlideTransitionStyle = SlideTransitionStyle.draw;
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: drawSlideDuration,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => buildDialogTransition(
              controller,
              const Center(
                child: SizedBox(width: 200, height: 100, child: Text('箱')),
              ),
            ),
          ),
        ),
      ),
    );
    controller.value = 0.5;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ScribbleLayerReveal), findsOneWidget);
    controller.value = 1;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('箱'), findsOneWidget);
  });

  testWidgets('描き以外でも木の形は同じ（再マウントされない）', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: drawSlideDuration,
    )..value = 1;
    addTearDown(controller.dispose);
    for (final style in SlideTransitionStyle.values) {
      activeSlideTransitionStyle = style;
      await tester.pumpWidget(
        MaterialApp(home: buildDialogTransition(controller, const Text('x'))),
      );
      expect(
        find.byType(ScribbleLayerReveal),
        findsOneWidget,
        reason: '$style',
      );
    }
  });
}
