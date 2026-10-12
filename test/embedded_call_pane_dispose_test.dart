import 'package:daidai/features/call/embedded_call_pane.dart';
import 'package:daidai/providers/chat_navigation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-10-13: `ConsumerState.dispose()`内で`ref`を使うとRiverpod 3系は`StateError`を
// 投げ、チャットペインが破棄される度に例外が出ていた。
void main() {
  testWidgets('アンマウントしても例外が出ず、会話の報告が解除される', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const conversation = ViewedDm('d1');

    Widget app({required bool mounted}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: mounted
            ? const EmbeddedCallPane(
                conversation: conversation,
                roomId: 'r1',
                child: SizedBox(),
              )
            : const SizedBox(),
      ),
    );

    await tester.pumpWidget(app(mounted: true));
    await tester.pump(); // 初回の報告（フレーム後）
    expect(container.read(activeConversationProvider), conversation);

    await tester.pumpWidget(app(mounted: false));
    await tester.pump(); // 後始末はマイクロタスクで行う
    expect(tester.takeException(), isNull);
    expect(container.read(activeConversationProvider), isNull);
    expect(container.read(embeddedCallShownProvider), isNull);
  });
}
