import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/theme/chalk/chalk_theme.dart';
import 'package:daidai/widgets/nav_chip.dart';

/// 再発防止（2026-11-27）。チョークで、明るい背景の時、選択中のメニューチップのアイコンが、
/// 選択の動き（液体・描き・滑り・囲み・無し）のどれでも、アクセント上の色（ここでは純白）の
/// 画素で描かれる。塗りの層が、アイコンを薄くしない（クリーム色に見えた）。
void main() {
  const accent = Color(0xFF4FB6B8);
  for (final motion in SelectionMotion.values) {
    testWidgets('チョーク ${motion.name}: 選択中のアイコンは純白', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(AppUiStyle.chalk),
            initialAccentColorProvider.overrideWithValue(accent),
            initialSelectionMotionProvider.overrideWithValue(motion),
          ],
          child: MaterialApp(
            theme: ChalkTheme.build(
              accent,
              null,
              background: const Color(0xFFF2F2F5),
              onAccentColor: const Color(0xFFFFFFFF),
            ),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: ChipNavShell(
                  icons: const [Icons.chat, Icons.person, Icons.settings],
                  iconSizes: const [28, 28, 28],
                  labels: const ['a', 'b', 'c'],
                  selectedIndex: 2,
                  onSelected: (_) {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      final rect = tester.getRect(find.byType(NavChip).at(2));
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var white = 0;
        var teal = 0;
        var grey = 0;
        for (
          var y = rect.center.dy.toInt() - 10;
          y < rect.center.dy.toInt() + 10;
          y++
        ) {
          for (
            var x = rect.center.dx.toInt() - 10;
            x < rect.center.dx.toInt() + 10;
            x++
          ) {
            final i = (y * img.width + x) * 4;
            final r = d.getUint8(i),
                g = d.getUint8(i + 1),
                bl = d.getUint8(i + 2);
            if (r == 255 && g == 255 && bl == 255) white++;
            if (r == 0x4f && g == 0xb6 && bl == 0xb8) teal++;
            // 灰色（白が薄くなった色）。
            if ((r - g).abs() < 6 && (g - bl).abs() < 6 && r > 150 && r < 252)
              grey++;
          }
        }
        expect(teal, greaterThan(50), reason: '塗りが無い');
        expect(white, greaterThan(100), reason: 'アイコンが白で描かれていない');
        expect(grey, lessThan(10), reason: 'アイコンが灰色に薄まっている');
      });
    });
  }
}
