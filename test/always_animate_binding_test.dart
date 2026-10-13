import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/always_animated_image.dart';

/// `AlwaysAnimateBinding`と同じ上書き（`disableAnimations`を常に偽）を、テスト用の
/// バインディングで再現する。
class _AlwaysAnimateTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableAnimations => false;
}

void main() {
  _AlwaysAnimateTestBinding();

  testWidgets('OSがアニメーション無効でも、AnimationControllerは通常の所要時間で進む', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(SemanticsBinding.instance.disableAnimations, isFalse);

    late AnimationController controller;
    await tester.pumpWidget(
      MaterialApp(home: _Host(onCreate: (c) => controller = c)),
    );
    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 5%（=40ms）で終わらず、まだ途中。
    expect(controller.value, greaterThan(0));
    expect(controller.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 800));
    expect(controller.value, 1);
  });

  testWidgets('Switchの切り替えがアニメーションする', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var value = false;
    await tester.pumpWidget(
      AlwaysAnimations(
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Switch(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // 途中経過のフレームがある（1フレームで終わらない）。
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onCreate});

  final void Function(AnimationController) onCreate;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    widget.onCreate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
