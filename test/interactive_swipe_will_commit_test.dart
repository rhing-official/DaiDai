import 'package:daidai/widgets/interactive_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('確定のアニメーションを始める時に、開き切る前にonWillCommitが呼ばれる', (tester) async {
    final events = <String>[];
    final controller = InteractiveSwipeBackController(
      vsync: const TestVSync(),
      onWillCommit: () => events.add('will'),
      onCommit: () => events.add('commit'),
      notifyNavigator: false,
    )..maxDrag = 400;
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    controller.syncFromExternalDrag(context, 300);
    controller.endExternalDrag(context, 800);
    // 開き切るアニメーションが終わる前に、先に呼ばれている。
    expect(events, ['will']);
    await tester.pumpAndSettle();
    expect(events, ['will', 'commit']);
  });

  testWidgets('元へ戻る（確定しない）時は、onWillCommitを呼ばない', (tester) async {
    final events = <String>[];
    final controller = InteractiveSwipeBackController(
      vsync: const TestVSync(),
      onWillCommit: () => events.add('will'),
      onCommit: () => events.add('commit'),
      notifyNavigator: false,
    )..maxDrag = 400;
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    controller.syncFromExternalDrag(context, 40);
    controller.endExternalDrag(context, 0);
    await tester.pumpAndSettle();
    expect(events, isEmpty);
  });
}
