import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/liquid_chip_highlight.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';
import 'package:daidai/widgets/scribble_paint.dart';

Widget _app(Widget child, AppUiStyle style) => ProviderScope(
  overrides: [
    initialAppUiStyleProvider.overrideWithValue(style),
    initialSelectionMotionProvider.overrideWithValue(SelectionMotion.draw),
  ],
  child: MaterialApp(home: Scaffold(body: Center(child: child))),
);

void main() {
  for (final style in [AppUiStyle.flat, AppUiStyle.chalk, AppUiStyle.gekiga]) {
    testWidgets('描き（$style）: 項目は、ペンで塗るように選択の見た目が現れる', (tester) async {
      final index = ValueNotifier<int>(0);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (_, i, _) => LiquidTileGroup(
              itemCount: 3,
              selectedIndex: i,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var k = 0; k < 3; k++)
                    LiquidTile(
                      index: k,
                      builder: (context, sel) => ListTile(
                        title: Text('項目$k'),
                        selected: sel,
                      ),
                    ),
                ],
              ),
            ),
          ),
          style,
        ),
      );
      await tester.pumpAndSettle();
      index.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(ScribbleReveal), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(ScribbleReveal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('描き（$style）: メニューチップは、ペンの層が動く', (tester) async {
      final index = ValueNotifier<int>(0);
      final keys = [for (var i = 0; i < 3; i++) GlobalKey()];
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (_, i, _) => LiquidChipStrip(
              entries: [
                for (var k = 0; k < 3; k++)
                  LiquidChipEntry(
                    chipKey: keys[k],
                    icon: Icons.home,
                    iconSize: 24,
                  ),
              ],
              selectedIndex: i,
              vertical: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var k = 0; k < 3; k++)
                    SizedBox(key: keys[k], width: 56, height: 56),
                ],
              ),
            ),
          ),
          style,
        ),
      );
      await tester.pumpAndSettle();
      index.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
