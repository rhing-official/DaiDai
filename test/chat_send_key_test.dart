import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:flutter/foundation.dart';
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
      overrides: [
        initialSendKeyModeProvider.overrideWithValue(mode),
        initialMessageTimeFormatProvider.overrideWithValue(MessageTimeFormat.h24),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialChatLayoutStyleProvider.overrideWithValue(ChatLayoutStyle.sideBySide),
      ],
      child: MaterialApp(
        home: ChatScreen(
          title: 'test',
          currentUserId: 'u1',
          isDm: true,
          messagesStream: Stream.value(<Message>[]),
          onSend: (content, {silent = false}) async =>
              sentMessages.add(_Sent(content, silent)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Enterキーでの送信/改行の振り分けは、物理キーボードが接続されている場合の
/// 挙動（_hasHardwareKeyboard）。Androidの実機ソフトウェアキーボードは
/// textInputAction.newlineの仕様上、改行キーを押しただけでも生のEnterキー
/// イベントを送出してしまうため、Enterキー単体はハードウェアキーボード
/// 接続の判定材料にしていない（chat_screen.dartの_onHardwareKeyEventの
/// コメント参照）。そのため、この振り分けロジックを検証するテストでは
/// 明示的にデスクトップ用TargetPlatformへ切り替えて「物理キーボード接続済み」
/// の状態を作る（デフォルトはflutter testの仕様によりTargetPlatform.android）。
/// debugDefaultTargetPlatformOverrideの後始末はtry/finallyで行う
/// （addTearDown等を使うと、テストバインディングの不変条件チェックが
/// finally/tearDownの実行より先に走ってしまい別のエラーになるため）。
Future<void> _withDesktopKeyboard(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('enterToSend: Enterのみで通常送信', (tester) async {
    await _withDesktopKeyboard(() async {
      final sent = <_Sent>[];
      await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sent, hasLength(1));
      expect(sent.single.content, 'hello');
      expect(sent.single.silent, isFalse);
    });
  });

  testWidgets('enterToSend: Shift+Enterは改行のみで送信しない', (tester) async {
    await _withDesktopKeyboard(() async {
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
  });

  testWidgets('enterToSend: Ctrl+Enterで通知せず送信', (tester) async {
    await _withDesktopKeyboard(() async {
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
  });

  testWidgets('ctrlEnterToSend: 素のEnterは改行のみで送信しない', (tester) async {
    await _withDesktopKeyboard(() async {
      final sent = <_Sent>[];
      await _pumpChatScreen(tester, mode: SendKeyMode.ctrlEnterToSend, sentMessages: sent);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'hello\n');
    });
  });

  testWidgets('ctrlEnterToSend: Ctrl+Enterで通常送信', (tester) async {
    await _withDesktopKeyboard(() async {
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
  });

  testWidgets('ctrlEnterToSend: Ctrl+Shift+Enterで通知せず送信', (tester) async {
    await _withDesktopKeyboard(() async {
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
  });

  testWidgets('送信ボタンの長押しで通知せず送信', (tester) async {
    // 送信ボタンはハードウェアキーボード未接続時のみ表示される
    // （Windows/Linux/macOSは常時接続扱いのため、そのままではボタンが出ない）。
    // ここではAndroidを模擬してソフトウェアキーボードのみの状況を再現する。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final sent = <_Sent>[];
      await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      await tester.longPress(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(sent, hasLength(1));
      expect(sent.single.content, 'hello');
      expect(sent.single.silent, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'モバイル（ソフトウェアキーボードのみ）でEnterキーを押しても送信されず、'
    '送信ボタンも消えない（回帰テスト）',
    (tester) async {
      // Androidのソフトウェアキーボードはtextinput.action.newlineの仕様上、
      // 改行キーを押しただけでも生のEnterキーイベントを送出するため、これを
      // 物理キーボード接続の根拠にすると誤検知し、送信ボタンが消えて改行も
      // できなくなってしまう（実機で報告された不具合）。Enterキー単体では
      // ハードウェアキーボード接続とみなさないことを確認する。
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final sent = <_Sent>[];
        await _pumpChatScreen(tester, mode: SendKeyMode.enterToSend, sentMessages: sent);

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(sent, isEmpty);
        expect(find.byIcon(Icons.send), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
