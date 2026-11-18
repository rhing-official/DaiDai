import 'package:daidai/features/auth/passkey_create_warning_dialog.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> openDialog(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await PasskeyCreateWarningDialog.show(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('「理解した」にチェックを入れるまで、続けられない', (tester) async {
    await openDialog(tester);
    expect(find.byType(PasskeyCreateWarningDialog), findsOneWidget);
    // 続けるボタンは、チェックするまで押せない。
    final continueButton = find.widgetWithText(FilledButton, '続ける');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
  });

  testWidgets('チェックして続けるとtrue、キャンセルはfalseを返す', (tester) async {
    bool? result;
    Future<void> pump() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await PasskeyCreateWarningDialog.show(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '続ける'));
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await pump();
    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
