import 'package:daidai/widgets/interactive_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内側の階層を1つ閉じた（`consumeBack`が真）右スワイプは、外側へ戻らず元の位置へ
/// 戻ることの検証（2026-10-15、ライセンス一覧の項目から1階層だけ戻る）。
Future<void> _swipe(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(50, 300));
  await gesture.moveBy(const Offset(500, 0));
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Widget _app({required VoidCallback onBack, bool Function()? consumeBack}) =>
    MaterialApp(
      home: Scaffold(
        body: InteractiveSwipeBackTransition(
          onBack: onBack,
          consumeBack: consumeBack,
          child: const SizedBox.expand(key: ValueKey('pane')),
        ),
      ),
    );

void main() {
  testWidgets('consumeBackが真なら、onBackを呼ばず元の位置へ戻る', (tester) async {
    var backed = 0;
    var consumed = 0;
    await tester.pumpWidget(
      _app(
        onBack: () => backed++,
        consumeBack: () {
          consumed++;
          return true;
        },
      ),
    );
    await _swipe(tester);
    expect(consumed, 1);
    expect(backed, 0);
    final dx = tester.getTopLeft(find.byKey(const ValueKey('pane'))).dx;
    expect(dx, 0, reason: '内側を閉じた時はペインが画面外へ出たままにならない');
  });

  testWidgets('consumeBackが偽なら従来どおりonBackを呼ぶ', (tester) async {
    var backed = 0;
    await tester.pumpWidget(
      _app(onBack: () => backed++, consumeBack: () => false),
    );
    await _swipe(tester);
    expect(backed, 1);
  });

  testWidgets('consumeBack未指定でも従来どおりonBackを呼ぶ', (tester) async {
    var backed = 0;
    await tester.pumpWidget(_app(onBack: () => backed++));
    await _swipe(tester);
    expect(backed, 1);
  });
}
