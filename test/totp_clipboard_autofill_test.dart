import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/utils/totp_clipboard_autofill.dart';

class _Host extends StatefulWidget {
  const _Host({required this.controller, required this.onFilled, this.active});

  final TextEditingController controller;
  final void Function(String) onFilled;
  final bool Function()? active;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TotpClipboardAutofill<_Host> {
  @override
  TextEditingController get totpCodeController => widget.controller;

  @override
  bool get totpAutofillActive => widget.active?.call() ?? true;

  @override
  void onTotpAutofilled(String code) => widget.onFilled(code);

  @override
  Widget build(BuildContext context) =>
      TextField(controller: widget.controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseTotpCode', () {
    test('6桁の数字を取り出す', () {
      expect(parseTotpCode('123456'), '123456');
      expect(parseTotpCode(' 123 456 '), '123456');
      expect(parseTotpCode('123-456'), '123456');
      expect(parseTotpCode('１２３４５６'), '123456');
    });

    test('6桁の数字以外はnull', () {
      expect(parseTotpCode(null), isNull);
      expect(parseTotpCode(''), isNull);
      expect(parseTotpCode('12345'), isNull);
      expect(parseTotpCode('1234567'), isNull);
      expect(parseTotpCode('abc123'), isNull);
      expect(parseTotpCode('code: 123456'), isNull);
    });
  });

  group('TotpClipboardAutofill', () {
    String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return clipboard == null
                  ? null
                  : <String, dynamic>{'text': clipboard};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<_HostState> pump(
      WidgetTester tester,
      TextEditingController c,
      List<String> filled, {
      bool Function()? active,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Host(controller: c, onFilled: filled.add, active: active),
          ),
        ),
      );
      return tester.state<_HostState>(find.byType(_Host));
    }

    testWidgets('6桁なら入力欄に入れて確定を1回呼ぶ。同じ値では繰り返さない', (tester) async {
      final c = TextEditingController();
      final filled = <String>[];
      final state = await pump(tester, c, filled);
      clipboard = '123 456';
      await state.checkTotpClipboard();
      expect(c.text, '123456');
      expect(filled, ['123456']);
      await state.checkTotpClipboard();
      expect(filled, ['123456']);
      clipboard = '654321';
      await state.checkTotpClipboard();
      expect(filled, ['123456', '654321']);
    });

    testWidgets('6桁以外のクリップボードや空では何も起きない', (tester) async {
      final c = TextEditingController();
      final filled = <String>[];
      final state = await pump(tester, c, filled);
      clipboard = 'hello';
      await state.checkTotpClipboard();
      clipboard = null;
      await state.checkTotpClipboard();
      expect(c.text, isEmpty);
      expect(filled, isEmpty);
    });

    testWidgets('入力欄が有効でない間は読まない', (tester) async {
      final c = TextEditingController();
      final filled = <String>[];
      var active = false;
      final state = await pump(tester, c, filled, active: () => active);
      clipboard = '123456';
      await state.checkTotpClipboard();
      expect(filled, isEmpty);
      active = true;
      await state.checkTotpClipboard();
      expect(filled, ['123456']);
    });

    testWidgets('アプリが前面に戻った時に確認する', (tester) async {
      final c = TextEditingController();
      final filled = <String>[];
      await pump(tester, c, filled);
      clipboard = '111222';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(filled, ['111222']);
    });
  });
}
