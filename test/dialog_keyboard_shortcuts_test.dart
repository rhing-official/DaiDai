import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/dialog_keyboard_shortcuts.dart';

Future<void> _open(
  WidgetTester tester,
  ValueNotifier<String> result, {
  bool withField = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final r = await showDialog<bool>(
              context: context,
              builder: (ctx) => KeyboardAlertDialog(
                content: withField ? const TextField(autofocus: true) : null,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('no'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('yes'),
                  ),
                ],
              ),
            );
            result.value = '$r';
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('$key で同意', (tester) async {
      final r = ValueNotifier('-');
      await _open(tester, r);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(r.value, 'true');
    });
  }
  for (final key in [LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete]) {
    testWidgets('$key で拒否', (tester) async {
      final r = ValueNotifier('-');
      await _open(tester, r);
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(r.value, 'null');
    });
  }
  testWidgets('入力欄フォーカス中のBackspaceではキャンセルしない', (tester) async {
    final r = ValueNotifier('-');
    await _open(tester, r, withField: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardAlertDialog), findsOneWidget);
    expect(r.value, '-');
  });
}
