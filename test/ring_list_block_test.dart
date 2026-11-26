import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';
import 'package:daidai/widgets/ring_list_scope.dart';

void main() {
  for (final style in [
    AppUiStyle.flat,
    AppUiStyle.block,
    AppUiStyle.chalk,
    AppUiStyle.kinari,
    AppUiStyle.gekiga,
  ]) {
    testWidgets('丸で囲む（$style）: 項目を1つのブロックにまとめ、選択中を枠で囲む', (tester) async {
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
              body: ValueListenableBuilder<int>(
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
                          builder: (context, sel) =>
                              ListTile(title: Text('項目$k'), selected: sel),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RingOutline), findsOneWidget);
      index.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
