import 'package:daidai/widgets/interactive_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StateProbe extends StatefulWidget {
  const _StateProbe();
  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Widget _app({required bool enabled, required VoidCallback onBack}) {
  return MaterialApp(
    home: InteractiveSwipeBackTransition(
      enabled: enabled,
      onBack: onBack,
      child: const _StateProbe(),
    ),
  );
}

void main() {
  testWidgets('enabled=falseでは右スワイプしてもonBackが呼ばれない', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_app(enabled: false, onBack: () => backs++));
    await tester.fling(find.byType(_StateProbe), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(backs, 0);
  });

  testWidgets('enabled=trueでは右スワイプでonBackが呼ばれる', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_app(enabled: true, onBack: () => backs++));
    await tester.fling(find.byType(_StateProbe), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('enabledを切り替えても子のStateは作り直されない', (tester) async {
    await tester.pumpWidget(_app(enabled: true, onBack: () {}));
    final before = tester.state(find.byType(_StateProbe));
    await tester.pumpWidget(_app(enabled: false, onBack: () {}));
    expect(tester.state(find.byType(_StateProbe)), same(before));
  });
}
