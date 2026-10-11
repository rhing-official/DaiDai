import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/destructive_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _textLeft(WidgetTester tester, {required bool align}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat)],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const ListTile(title: Text('通常の項目')),
              ListTile(
                title: DestructiveLabel('削除', alignTextWithSiblings: align),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return tester.getTopLeft(find.text('削除')).dx;
}

void main() {
  testWidgets('alignTextWithSiblingsで、文字の左端が他の項目の文字と揃う', (tester) async {
    final normal = await _textLeft(tester, align: false);
    final base = tester.getTopLeft(find.text('通常の項目')).dx;
    // 既定ではピルの左端が揃い、文字はパディング分右にずれる。
    expect(normal, base + 10);

    final aligned = await _textLeft(tester, align: true);
    expect(aligned, base);
  });
}
