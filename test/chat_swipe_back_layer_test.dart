import 'package:daidai/widgets/interactive_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 全画面のメッセージ画面を右スワイプで閉じる時、上に層（寄合の切り替えの履歴など）が
// あると、`GoRoute.onExit`がpopを止める。止められた後に、画面が右へ消えたまま固まらない
// こと（2026-11-15）。
void main() {
  Future<GoRouter> pump(
    WidgetTester tester, {
    required bool withConsumeBack,
    required List<int> layers,
  }) async {
    late final GoRouter router;
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => router.push('/chat'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat',
          onExit: (_, _) {
            if (layers.isNotEmpty) {
              layers.removeLast();
              return false;
            }
            return true;
          },
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            opaque: false,
            transitionsBuilder: (_, animation, _, child) => child,
            child: InteractiveSwipeBackTransition(
              onBack: () {
                if (router.canPop()) router.pop();
              },
              consumeBack: withConsumeBack
                  ? () {
                      if (layers.isEmpty) return false;
                      layers.removeLast();
                      return true;
                    }
                  : null,
              child: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('chat-button'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('chat-button'), findsOneWidget);
    return router;
  }

  testWidgets('層があっても、右スワイプの後に画面が元の位置へ戻り、操作できる', (tester) async {
    final layers = [1];
    await pump(tester, withConsumeBack: true, layers: layers);

    await tester.fling(find.text('chat-button'), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();

    expect(layers, isEmpty, reason: '層が1つ閉じた');
    // まだメッセージ画面にいて、画面は画面内にあり、タップできる。
    final center = tester.getCenter(find.text('chat-button'));
    expect(center.dx, greaterThan(0));
    expect(center.dx, lessThan(800));
    expect(find.text('chat-button').hitTestable(), findsOneWidget);

    // もう一度スワイプすると、一覧へ出る。
    await tester.fling(find.text('chat-button'), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('chat-button'), findsNothing);
  });

  testWidgets('層が無ければ、今までどおり一覧へ出る', (tester) async {
    await pump(tester, withConsumeBack: true, layers: []);
    await tester.fling(find.text('chat-button'), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
