import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/toggles/app_checkbox.dart';
import 'package:daidai/widgets/toggles/app_radio.dart';
import 'package:daidai/widgets/toggles/app_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {AppUiStyle style = AppUiStyle.flat}) {
  return ProviderScope(
    overrides: [initialAppUiStyleProvider.overrideWithValue(style)],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  for (final style in AppUiStyle.values) {
    testWidgets('スイッチはタップで切り替わる（$style）', (tester) async {
      var value = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => AppSwitch(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
          style: style,
        ),
      );
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      expect(value, isTrue);
      // 弾みのアニメーションの途中がある。
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(value, isFalse);
    });
  }

  testWidgets('スイッチはドラッグでも切り替わり、無効なら変わらない', (tester) async {
    var value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => AppSwitch(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(AppSwitch), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(value, isTrue);

    await tester.pumpWidget(
      host(const AppSwitch(value: false, onChanged: null)),
    );
    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(find.byType(AppSwitch), findsOneWidget);
  });

  testWidgets('スイッチの行は行全体のタップで切り替わる', (tester) async {
    var value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => AppSwitchListTile(
            title: const Text('項目'),
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('項目'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });

  testWidgets('チェックボックスはタップで切り替わる', (tester) async {
    bool? value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => AppCheckboxListTile(
            title: const Text('項目'),
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('項目'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });

  testWidgets('ラジオはRadioGroupの値を選ぶ', (tester) async {
    String? picked = 'a';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => RadioGroup<String>(
            groupValue: picked,
            onChanged: (v) => setState(() => picked = v),
            child: const Column(
              children: [
                AppRadioListTile<String>(value: 'a', title: Text('A')),
                AppRadioListTile<String>(value: 'b', title: Text('B')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });
}
