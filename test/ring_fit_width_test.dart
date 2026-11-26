import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';

void main() {
  for (final style in [AppUiStyle.flat, AppUiStyle.chalk, AppUiStyle.block]) {
    testWidgets('囲み（$style）: 選択を変えても、項目は横いっぱいのまま', (tester) async {
      final index = ValueNotifier<int>(0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(style),
            initialSelectionMotionProvider.overrideWithValue(
              SelectionMotion.ring,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  child: ValueListenableBuilder<int>(
                    valueListenable: index,
                    builder: (_, i, _) => LiquidTileGroup(
                      itemCount: 2,
                      selectedIndex: i,
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (var k = 0; k < 2; k++)
                            LiquidTile(
                              index: k,
                              builder: (context, sel) => blockFitWidth(
                                ListTile(title: Text('項目$k'), selected: sel),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> check() async {
        for (final t in tester.widgetList<ListTile>(find.byType(ListTile))) {
          expect(tester.getSize(find.byWidget(t)).width, 284);
        }
      }

      await tester.pumpAndSettle();
      await check();
      index.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await check();
      await tester.pumpAndSettle();
      await check();
    });
  }
}
