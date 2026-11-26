import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/features/chat/talks_tab.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';

void main() {
  for (final style in [AppUiStyle.flat, AppUiStyle.chalk, AppUiStyle.block]) {
    testWidgets('囲みの一対・広場のタブは、同じ幅（$style）', (tester) async {
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
              body: Row(
                children: [
                  Expanded(
                    child: LiquidTileGroup(
                      itemCount: 2,
                      selectedIndex: 0,
                      child: IntrinsicWidth(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: CategoryTab(
                                liquidIndex: 0,
                                tutorialTargetId: 'a',
                                label: '一対',
                                count: 8,
                                selected: true,
                                onTap: () {},
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: CategoryTab(
                                liquidIndex: 1,
                                tutorialTargetId: 'b',
                                label: '広場',
                                count: 4,
                                selected: true,
                                onTap: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(CategoryTab);
      final a = tester.getSize(tabs.at(0)).width;
      final b = tester.getSize(tabs.at(1)).width;
      expect(a, b);
    });
  }
}
