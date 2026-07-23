import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Enterキーの送信/改行/通知なし送信の振り分けが実際に効くかどうかを検証する回帰テスト。
// Focus.onKeyEventでEnterを消費する実装がFlutterの本物のキーイベント経路
// （EditableTextの改行挿入と競合しないか）は理屈だけでは確信が持てないため、
// 実際にキーイベントを流して確認する。
class _Sent {
  const _Sent(this.content, this.silent);
  final String content;
  final bool silent;
}

Future<void> _pumpChatScreen(
  WidgetTester tester, {
  required SendKeyMode mode,
  required List<_Sent> sentMessages,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [initialSendKeyModeProvider.overrideWithValue(mode)],
      child: MaterialApp(
        home: ChatScreen(
          title: 'test',
          currentUserId: 'u1',
          messagesStream: Stream.value(<Message>[]),
          onSend: (content, {silent = false}) async =>
              sentMessages.add(_Sent(content, silent)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('enterToSend: Enterのみで通常送信', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.content, 'hello');
    expect(sent.single.silent, isFalse);
  });

  testWidgets('enterToSend: Shift+Enterは改行のみで送信しない', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hello\n');
  });

  testWidgets('enterToSend: Ctrl+Enterで通知せず送信', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.content, 'hello');
    expect(sent.single.silent, isTrue);
  });

  testWidgets('ctrlEnterToSend: 素のEnterは改行のみで送信しない', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.ctrlEnterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hello\n');
  });

  testWidgets('ctrlEnterToSend: Ctrl+Enterで通常送信', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.ctrlEnterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.content, 'hello');
    expect(sent.single.silent, isFalse);
  });

  testWidgets('ctrlEnterToSend: Ctrl+Shift+Enterで通知せず送信', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.ctrlEnterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.content, 'hello');
    expect(sent.single.silent, isTrue);
  });

  testWidgets('送信ボタンの長押しで通知せず送信', (tester) async {
    final sent = <_Sent>[];
    await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.longPress(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.content, 'hello');
    expect(sent.single.silent, isTrue);
  });
}
