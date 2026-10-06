import 'package:daidai/router/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  _chatRouteTests();
  testWidgets('ブラウザの戻る（ベースルートのpop）でダイアログ→ペインの順に閉じ、アプリの外へは出ない', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final backStack = container.read(backStackControllerProvider);
    late final GoRouter router;
    router = GoRouter(
      observers: [BackStackObserver(backStack)],
      redirect: (context, state) {
        final path = state.uri.path;
        if (path.startsWith('/_b/')) {
          final id = int.tryParse(path.substring(4));
          if (id == null || !backStack.isLive(id)) return '/';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/_b/:id',
          pageBuilder: (context, state) => BackPage(
            id: int.parse(state.pathParameters['id']!),
            key: state.pageKey,
          ),
        ),
        GoRoute(path: '/', builder: (context, state) => const _Home()),
      ],
    );
    backStack.attach(push: (id) => router.push('/_b/$id'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // ベースが積まれている（ホームより前へは戻れない）。
    expect(router.canPop(), isTrue);

    // ペインを開く。
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('pane'), findsOneWidget);

    // ブラウザの戻る相当（先頭の透明ルートのpop）→ペインが閉じ、入口の
    // ベースルートは積み直される。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('pane'), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/_b/0',
    );

    // ダイアログを開いて戻る操作 → ダイアログだけが閉じる（ペインは残る）。
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dialog-body'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('dialog-body'), findsNothing);
    expect(find.text('pane'), findsOneWidget);

    // 続けて戻るとペインが閉じる。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('pane'), findsNothing);

    // 何も開いていない状態で戻っても、アプリの外へ出ずホームのまま。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/_b/0',
    );
  });
}

void _chatRouteTests() {
  Future<GoRouter> pumpApp(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final backStack = container.read(backStackControllerProvider);
    final router = GoRouter(
      observers: [BackStackObserver(backStack)],
      redirect: (context, state) {
        if (state.uri.path == '/chat' && state.extra == null) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('list'),
                TextButton(
                  onPressed: () => context.push('/chat', extra: 'args'),
                  child: const Text('to-chat'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/chat',
          onExit: (context, state) => !backStack.closeTopOverlay(),
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('chat'),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) =>
                        const AlertDialog(content: Text('dialog-body')),
                  ),
                  child: const Text('dialog'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          const Scaffold(body: Text('viewer')),
                    ),
                  ),
                  child: const Text('viewer-open'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('寄合（/chat）でポップアップ・ビューアを開いて戻ると、それだけ閉じて寄合に留まる', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = await pumpApp(tester, container);

    await tester.tap(find.text('to-chat'));
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);

    // ポップアップを開いて、ブラウザの戻る相当（遷移）→ポップアップだけ閉じる。
    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dialog-body'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('dialog-body'), findsNothing);
    expect(find.text('chat'), findsOneWidget);

    // 全画面ビューアも同様に閉じるだけ。
    await tester.tap(find.text('viewer-open'));
    await tester.pumpAndSettle();
    expect(find.text('viewer'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('viewer'), findsNothing);
    expect(find.text('chat'), findsOneWidget);

    // 何も開いていなければ通常どおり一覧へ戻る。
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsNothing);
    expect(find.text('list'), findsOneWidget);
  });

  testWidgets('引数（extra）が無い/chatへ来た（ブラウザの進む・リロード）ら一覧へ戻す', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = await pumpApp(tester, container);

    router.go('/chat'); // extraなし
    await tester.pumpAndSettle();
    expect(find.text('list'), findsOneWidget);
    expect(find.text('chat'), findsNothing);
  });
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return BackBaseGuard(
      child: Scaffold(
        body: BackEntry(
          scope: BackScope.talks,
          active: _open,
          onBack: () => setState(() => _open = false),
          child: _open
              ? Column(
                  children: [
                    const Text('pane'),
                    TextButton(
                      onPressed: () => setState(() => _open = false),
                      child: const Text('close'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) =>
                            const AlertDialog(content: Text('dialog-body')),
                      ),
                      child: const Text('dialog'),
                    ),
                  ],
                )
              : TextButton(
                  onPressed: () => setState(() => _open = true),
                  child: const Text('open'),
                ),
        ),
      ),
    );
  }
}
