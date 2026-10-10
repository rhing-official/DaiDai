import 'package:daidai/features/not_found/not_found_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) => const NotFoundScreen(),
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('HOME')),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, GoRouter router, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未定義のURLで「404 美術館」が出て、展示は6点のうち1点だけ表示される', (tester) async {
    final router = _router();
    await _pump(tester, router);
    router.go('/a');
    await tester.pumpAndSettle();

    expect(find.text('404 MUSEUM'), findsOneWidget);
    expect(find.text('お探しのページは見つかりませんでした'), findsOneWidget);
    expect(find.textContaining('存在しないページ特別展'), findsOneWidget);
    expect(find.text('トップページへ戻る'), findsOneWidget);
    expect(find.text('お問い合わせ'), findsOneWidget);

    final shown = museumExhibits
        .where((e) => find.text(e.title).evaluate().isNotEmpty)
        .toList();
    expect(shown, hasLength(1));
    expect(find.text(shown.single.caption), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('「トップページへ戻る」でホームへ戻る', (tester) async {
    final router = _router();
    await _pump(tester, router);
    router.go('/zzz');
    await tester.pumpAndSettle();
    expect(find.text('404 MUSEUM'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('トップページへ戻る'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('トップページへ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('404 MUSEUM'), findsNothing);
  });

  testWidgets('狭い画面でも例外なく表示でき、ボタンまでスクロールで届く', (tester) async {
    final router = _router();
    await _pump(tester, router, size: const Size(390, 800));
    router.go('/a');
    await tester.pumpAndSettle();

    expect(find.text('404 MUSEUM'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('お問い合わせ'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('お問い合わせ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
