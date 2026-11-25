import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('地はアクセントカラー、文字は設定のアクセント上の文字色', (tester) async {
    const accent = Color(0xFF123456);
    const onAccent = Color(0xFFABCDEF);
    var retried = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(
              primary: accent,
              onPrimary: onAccent,
            ),
          ),
          home: Scaffold(body: ScreenDeliveryNotice(onRetry: () => retried++)),
        ),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(ScreenDeliveryNotice),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, accent);

    final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber));
    expect(icon.color, onAccent);

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ScreenDeliveryNotice),
        matching: find.byType(Text),
      ),
    );
    final message = texts.first;
    expect(message.style?.color, onAccent);

    await tester.tap(find.byType(TextButton));
    expect(retried, 1);
  });
}
