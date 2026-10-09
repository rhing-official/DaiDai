import 'package:daidai/widgets/interactive_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navigatorへの`didStartUserGesture`/`didStopUserGesture`が必ずペアになる
/// ことの検証（終了が呼ばれないと全ルートが`IgnorePointer`になり、アプリ全体が
/// タッチ不能になる不具合の回帰テスト、2026-10-07）。
class _Host extends StatefulWidget {
  const _Host({required this.notify});
  final bool notify;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final InteractiveSwipeBackController controller =
      InteractiveSwipeBackController(
        vsync: this,
        onCommit: () {},
        notifyNavigator: widget.notify,
      )..maxDrag = 400;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

NavigatorState _nav(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Future<_HostState> _pump(WidgetTester tester, {bool notify = true}) async {
  await tester.pumpWidget(MaterialApp(home: _Host(notify: notify)));
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('ドラッグ開始でNavigatorが通知され、キャンセルで必ず解除される', (tester) async {
    final host = await _pump(tester);
    host.controller.syncFromExternalDrag(
      tester.element(find.byType(_Host)),
      120,
    );
    expect(_nav(tester).userGestureInProgress, isTrue);

    host.controller.cancelExternalDrag();
    await tester.pumpAndSettle();
    expect(_nav(tester).userGestureInProgress, isFalse);
    expect(host.controller.isGestureActive, isFalse);
    expect(host.controller.progress.value, 0);
  });

  testWidgets('終了（endExternalDrag）でも解除される', (tester) async {
    final host = await _pump(tester);
    final context = tester.element(find.byType(_Host));
    host.controller.syncFromExternalDrag(context, 300);
    host.controller.endExternalDrag(context, 0);
    await tester.pumpAndSettle();
    expect(_nav(tester).userGestureInProgress, isFalse);
  });

  testWidgets('notifyNavigator:falseではNavigatorへ通知しない', (tester) async {
    final host = await _pump(tester, notify: false);
    host.controller.syncFromExternalDrag(
      tester.element(find.byType(_Host)),
      120,
    );
    expect(_nav(tester).userGestureInProgress, isFalse);
    host.controller.cancelExternalDrag();
    await tester.pumpAndSettle();
    expect(_nav(tester).userGestureInProgress, isFalse);
  });

  testWidgets('ドラッグ中にウィジェットが破棄されても解除される', (tester) async {
    final host = await _pump(tester);
    host.controller.syncFromExternalDrag(
      tester.element(find.byType(_Host)),
      120,
    );
    final navigator = _nav(tester);
    expect(navigator.userGestureInProgress, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('InteractiveSwipeBackTransitionのドラッグがキャンセルされても解除される', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveSwipeBackTransition(
          onBack: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(100, 300));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(_nav(tester).userGestureInProgress, isTrue);

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_nav(tester).userGestureInProgress, isFalse);
  });
}
