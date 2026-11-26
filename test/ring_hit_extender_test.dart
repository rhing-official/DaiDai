import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
    // 左右の端（余白の中）
    await tester.tapAt(Offset(2, origin.dy + 20));
    await tester.tapAt(Offset(298, origin.dy + 20));
    // 項目の内側
    await tester.tapAt(Offset(150, origin.dy + 20));
    expect(taps, 3);
  });
}
