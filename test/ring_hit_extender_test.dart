import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/theme/block/block_theme.dart';
import 'package:daidai/widgets/ring_list_scope.dart';

void main() {
  testWidgets('囲み: 項目の左右の余白（8px）を押しても、その高さの項目を押したことになる', (tester) async {
    var taps = 0;
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
                child: RingListBlock(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    children: [
                      ListTile(title: const Text('A'), onTap: () => taps++),
                      ListTile(title: const Text('B'), onTap: () {}),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(ListTile).first);
    expect(origin.dy, 10);
    // 左右の端（余白の中）
    await tester.tapAt(Offset(2, origin.dy + 20));
    await tester.tapAt(Offset(298, origin.dy + 20));
    // 項目の内側
    await tester.tapAt(Offset(150, origin.dy + 20));
    // 上端・下端の余白（ブロックの角）
    await tester.tapAt(Offset(2, 2));
    await tester.tapAt(Offset(150, 1));
    expect(taps, 5);
  });

  testWidgets('囲み: 項目の箱が、文字の幅に縮まず、横いっぱいに押せる', (tester) async {
    var taps = 0;
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
                child: RingListBlock(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      blockFitWidth(
                        ListTile(title: const Text('A'), onTap: () => taps++),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ListTile)).width, 284);
    await tester.tapAt(const Offset(250, 20));
    expect(taps, 1);
  });
}
