import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/toggles/app_radio.dart';

void main() {
  testWidgets('ラジオを選び直すと、丸が滑って移り、終わると重ねた丸が残らない', (tester) async {
    var value = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RadioGroup<int>(
                groupValue: value,
                onChanged: (v) => setState(() => value = v!),
                child: const Column(
                  children: [
                    AppRadioListTile<int>(value: 0, title: Text('a')),
                    AppRadioListTile<int>(value: 1, title: Text('b')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final overlayChildren = find.descendant(
      of: find.byType(Overlay),
      matching: find.byType(Positioned),
    );
    final before = overlayChildren.evaluate().length;
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    // 滑っている間は、重ね描きの丸が1つ増える。
    expect(overlayChildren.evaluate().length, before + 1);
    await tester.pumpAndSettle();
    expect(overlayChildren.evaluate().length, before);
    expect(value, 1);
  });

  testWidgets('選んだ瞬間に行がずれても、丸はずれた後の行から行へ滑る', (tester) async {
    var value = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RadioGroup<int>(
                groupValue: value,
                onChanged: (v) => setState(() => value = v!),
                child: Column(
                  children: [
                    // 選ぶと、全ての行が下へ100ずれる。
                    SizedBox(height: value == 0 ? 0 : 100),
                    const AppRadioListTile<int>(value: 0, title: Text('a')),
                    const AppRadioListTile<int>(value: 1, title: Text('b')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final marks = find.byType(AppRadioMark);
    final aY = tester.getCenter(marks.at(0)).dy;
    final bY = tester.getCenter(marks.at(1)).dy;
    final dot = find.descendant(
      of: find.byType(Overlay),
      matching: find.byType(Positioned),
    );
    // 滑っている丸は、ずれた後の2つの行の間に在る（ずれる前の位置からは出ない）。
    final y = tester.getCenter(dot.last).dy;
    expect(y, greaterThanOrEqualTo(aY - 1));
    expect(y, lessThanOrEqualTo(bY + 1));
    await tester.pumpAndSettle();
  });
}
