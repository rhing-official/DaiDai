import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/chalk_nav_bar.dart';
import 'package:daidai/widgets/liquid_chip_highlight.dart';

void main() {
  for (final style in AppUiStyle.values.where((s) => s != AppUiStyle.glass)) {
    testWidgets('丸で囲む（$style）: 選択が移ると、帯の描画が少しずつ変わる', (tester) async {
      final index = ValueNotifier<int>(0);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(style),
            initialSelectionMotionProvider.overrideWithValue(
              SelectionMotion.ring,
            ),
          ],
          child: MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: index,
              builder: (_, i, _) => Center(
                child: RepaintBoundary(
                  key: key,
                  child: NavChipBand(
                    entries: const [],
                    selectedIndex: i,
                    vertical: false,
                    child: const SizedBox(width: 300, height: 56),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      index.value = 2;
      await tester.pump();
      // 動いている途中のフレームが有る（直ちに終わらない）。
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  }
}
