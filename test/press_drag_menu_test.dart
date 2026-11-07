import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/widgets/press_drag_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _pump(WidgetTester tester, {bool enabled = true}) async {
  final selected = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.block),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: PressDragMenuButton<String>(
              enabled: enabled,
              onSelected: selected.add,
              items: const [
                PressDragMenuItem(value: 'a', icon: Icons.add, label: '項目A'),
                PressDragMenuItem(value: 'b', icon: Icons.remove, label: '項目B'),
              ],
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return selected;
}

void main() {
  testWidgets('押して項目までなぞって離すと選べる', (tester) async {
    final selected = await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.add)),
    );
    await tester.pump();
    expect(find.text('項目B'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('項目B')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(selected, ['b']);
    expect(find.text('項目A'), findsNothing);
  });

  testWidgets('動かさず離すとメニューは開いたままで、タップで選べる', (tester) async {
    final selected = await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.add)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('項目A'), findsOneWidget);
    expect(selected, isEmpty);
    await tester.tap(find.text('項目A'));
    await tester.pump();
    expect(selected, ['a']);
  });

  testWidgets('無効の間は開かない', (tester) async {
    await _pump(tester, enabled: false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.add)),
    );
    await tester.pump();
    expect(find.text('項目A'), findsNothing);
    await gesture.up();
  });
}
