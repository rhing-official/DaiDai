import 'package:daidai/features/settings/settings_accordion_section.dart';
import 'package:daidai/providers/settings_expansion_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 設定の折りたたみの開閉は、別のカテゴリへ移って戻っても保たれる（2026-11-06）。
void main() {
  testWidgets('開いた折りたたみは、作り直しても開いたまま', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget host({required bool show}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: show
              ? const SettingsAccordionSection(
                  stateKey: 'test.section',
                  title: '詳細設定',
                  children: [Text('中身')],
                )
              : const SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpWidget(host(show: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細設定'));
    await tester.pumpAndSettle();
    expect(container.read(settingsExpansionProvider)['test.section'], isTrue);

    // 別のカテゴリへ移る（この部品が破棄される）→戻る。
    await tester.pumpWidget(host(show: false));
    await tester.pumpWidget(host(show: true));
    await tester.pumpAndSettle();
    expect(container.read(settingsExpansionProvider)['test.section'], isTrue);
    // 閉じる操作も保たれる。
    await tester.tap(find.text('詳細設定'));
    await tester.pumpAndSettle();
    expect(container.read(settingsExpansionProvider)['test.section'], isFalse);
  });
}
