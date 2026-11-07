import 'package:daidai/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('pushした/chat/*は、currentConfiguration.uriには出なくても検出できる', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/chat/dm',
          builder: (_, _) => const Scaffold(body: Text('chat')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(isFullscreenChatOpen(router), isFalse);

    router.push('/chat/dm');
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);
    // go_routerの仕様: uriは命令的なルートを反映しない（ここでは'/'のまま）。
    expect(
      router.routerDelegate.currentConfiguration.uri.path.startsWith('/chat/'),
      isFalse,
    );
    expect(isFullscreenChatOpen(router), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(isFullscreenChatOpen(router), isFalse);
  });
}
