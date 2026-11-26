import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/ring_list_scope.dart';

void main() {
  testWidgets('囲みの一覧: 選択が移ると、枠が次の項目へ滑る', (tester) async {
    final index = ValueNotifier<int>(0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
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
                height: 400,
                child: ValueListenableBuilder<int>(
                  valueListenable: index,
                  builder: (_, i, _) => RingListBlock(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (var k = 0; k < 4; k++)
                          Builder(
                            builder: (context) {
                              final tile = ListTile(
                                title: Text('項目$k'),
                                onTap: () => index.value = k,
                              );
                              final style = RingListScope.styleOf(context)!;
                              return k == i
                                  ? RingSelectedMarker(
                                      style: style,
                                      child: tile,
                                    )
                                  : tile;
                            },
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
    final tile0 = tester.getRect(find.byType(ListTile).at(0));
    expect(tester.getRect(find.byType(RingOutline)).top, closeTo(tile0.top, 1));

    final tile2 = tester.getRect(find.byType(ListTile).at(2));
    index.value = 2;
    await tester.pump(); // 組み立て
    await tester.pump(); // 組み立て後の位置の登録
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getRect(find.byType(RingOutline)).top;
    expect(mid, greaterThan(tile0.top + 1));
    expect(mid, lessThan(tile2.top - 1));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(RingOutline)).top, closeTo(tile2.top, 1));
  });
}
