import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/liquid_chip_highlight.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';

Widget _app(Widget child, AppUiStyle style) => ProviderScope(
  overrides: [
    initialAppUiStyleProvider.overrideWithValue(style),
    initialSelectionMotionProvider.overrideWithValue(SelectionMotion.slide),
  ],
  child: MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

Widget _group(
  ValueNotifier<int> index,
  ValueNotifier<double?> external,
  List<List<bool>> log,
) => ValueListenableBuilder<int>(
  valueListenable: index,
  builder: (_, i, _) => LiquidTileGroup(
    itemCount: 3,
    selectedIndex: i,
    slidePosition: external,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < 3; k++)
          LiquidTile(
            index: k,
            builder: (context, sel) {
              if (log.length <= k) log.add([]);
              log[k].add(sel);
              return SizedBox(
                height: 48,
                width: 200,
                child: Text('項目$k${sel ? "*" : ""}'),
              );
            },
          ),
      ],
    ),
  ),
);

void main() {
  test('SelectionMotion.parseはslideを読む', () {
    expect(SelectionMotion.parse('slide'), SelectionMotion.slide);
    expect(SelectionMotion.parse('unknown'), isNull);
  });

  for (final style in [AppUiStyle.flat, AppUiStyle.chalk, AppUiStyle.gekiga]) {
    testWidgets('滑り（$style）: 選択を移すと、塗りが途中の項目を経て移る', (tester) async {
      final index = ValueNotifier<int>(0);
      final external = ValueNotifier<double?>(null);
      await tester.pumpWidget(_app(_group(index, external, []), style));
      await tester.pumpAndSettle();
      expect(find.text('項目0*'), findsOneWidget);

      index.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      // 途中: 塗りが1番に掛かり、1番は、選ばれた見た目と選ばれていない見た目の両方が重なる。
      expect(find.text('項目1*'), findsOneWidget);
      expect(find.text('項目1'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('項目2*'), findsOneWidget);
      expect(find.text('項目0*'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('滑り: 外から渡した位置に、塗りが追従する', (tester) async {
    final index = ValueNotifier<int>(0);
    final external = ValueNotifier<double?>(null);
    await tester.pumpWidget(_app(_group(index, external, []), AppUiStyle.flat));
    await tester.pumpAndSettle();

    external.value = 1.0;
    await tester.pump();
    expect(find.text('項目1*'), findsOneWidget);
    expect(find.text('項目1'), findsNothing);
    expect(find.text('項目0*'), findsNothing);

    external.value = 0.5;
    await tester.pump();
    // 0番と1番の中間: どちらも、2つの見た目が重なる（半分ずつ）。
    expect(find.text('項目0*'), findsOneWidget);
    expect(find.text('項目0'), findsOneWidget);
    expect(find.text('項目1*'), findsOneWidget);
    expect(find.text('項目1'), findsOneWidget);

    // 離すと、選ばれている項目へ収まる。
    external.value = null;
    await tester.pumpAndSettle();
    expect(find.text('項目0*'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑り: メニューチップは、塗りの層を描く', (tester) async {
    final keys = [for (var i = 0; i < 3; i++) GlobalKey()];
    final index = ValueNotifier<int>(0);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, _) => LiquidChipStrip(
            selectedIndex: i,
            vertical: false,
            entries: [
              for (final k in keys)
                LiquidChipEntry(chipKey: k, icon: Icons.settings, iconSize: 24),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in keys) SizedBox(key: k, width: 56, height: 56),
              ],
            ),
          ),
        ),
        AppUiStyle.flat,
      ),
    );
    await tester.pumpAndSettle();
    index.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
