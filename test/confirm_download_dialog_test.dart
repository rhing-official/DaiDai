import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/confirm_download_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ダウンロード確認ダイアログの回帰テスト（キャンセルならfalse、確定ならtrue）。
Future<bool?> _open(
  WidgetTester tester,
  AppUiStyle style,
  String button,
) async {
  bool? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(Colors.orange),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(style),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async =>
                result = await confirmDownload(context, ref, fileName: 'メモ.md'),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('「メモ.md」をダウンロードします。'), findsOneWidget);
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  for (final style in [AppUiStyle.flat, AppUiStyle.glass]) {
    testWidgets('$style: ダウンロードでtrue', (tester) async {
      expect(await _open(tester, style, 'ダウンロード'), isTrue);
    });
    testWidgets('$style: キャンセルでfalse', (tester) async {
      expect(await _open(tester, style, 'キャンセル'), isFalse);
    });
  }
}
