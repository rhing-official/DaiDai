import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';
import 'package:daidai/widgets/slide_select_list.dart';

void main() {
  testWidgets('囲み: 何回押しても、文字の外（横いっぱい）で押せる', (tester) async {
    final index = ValueNotifier<int>(0);
    final log = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.chalk),
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
                    itemCount: 3,
                    selectedIndex: i,
                    child: ListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (var k = 0; k < 3; k++)
                          LiquidTile(
                            index: k,
                            builder: (context, sel) => blockFitWidth(
                              ListTile(
                                title: Text('項目$k'),
                                selected: sel,
                                onTap: () {
                                  log.add(k);
                                  index.value = k;
                                },
                              ),
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
    await tester.pumpAndSettle();
    final tops = [
      for (var k = 0; k < 3; k++)
        tester.getTopLeft(find.byType(ListTile).at(k)).dy,
    ];
    for (final order in [1, 2, 0, 1, 2, 0]) {
      await tester.tapAt(Offset(260, tops[order] + 28));
      await tester.pumpAndSettle();
    }
    expect(log, [1, 2, 0, 1, 2, 0]);
  });
}
