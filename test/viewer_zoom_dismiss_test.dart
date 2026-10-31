import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('拡大中は下スワイプで閉じず、等倍に戻すと閉じる', (tester) async {
    var dismissed = 0;
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: PinchPriorityPageView(
          controller: PageController(),
          itemCount: 1,
          onDismiss: () => dismissed++,
          itemBuilder: (_, _) => ZoomReporter(
            controller: controller,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    await tester.fling(find.byType(SizedBox).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(dismissed, 0);

    controller.value = Matrix4.identity();
    await tester.pump();
    await tester.fling(find.byType(SizedBox).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });
}
