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

/// 再発防止（2026-11-27）。メニューチップを選んだ瞬間に、アイコンがアクセント上の色へ変わらない。
/// 色は、塗りが届いた範囲だけ変わる（設定の項目と同じ）。ここでは、アクセント上の色を赤にして、
/// 選んで1フレーム後は赤の画素がほぼ無く、塗りが収まった後は十分に有ることを確かめる。
void main() {
  const accent = Color(0xFF4FB6B8);
  const onAccent = Color(0xFFFF0000);
  final cases = [
    for (final style in [AppUiStyle.flat, AppUiStyle.chalk])
      for (final motion in [
        SelectionMotion.liquid,
        SelectionMotion.draw,
        SelectionMotion.slide,
      ])
        (style, motion),
  ];
  for (final (style, motion) in cases) {
    testWidgets('${style.name} ${motion.name}: 選んだ瞬間は変わらず、塗りの後に変わる', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      var selected = 0;
      late StateSetter set;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(style),
            initialAccentColorProvider.overrideWithValue(accent),
            initialSelectionMotionProvider.overrideWithValue(motion),
          ],
          child: MaterialApp(
            theme: style == AppUiStyle.chalk
                ? ChalkTheme.build(
                    accent,
                    null,
                    background: const Color(0xFFF2F2F5),
                    onAccentColor: onAccent,
                  )
                : ThemeData(
                    colorScheme: const ColorScheme.light(
                      primary: accent,
                      onPrimary: onAccent,
                    ),
                  ),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    set = setState;
                    return ChipNavShell(
                      icons: const [Icons.chat, Icons.person, Icons.settings],
                      iconSizes: const [28, 28, 28],
                      labels: const ['a', 'b', 'c'],
                      selectedIndex: selected,
                      onSelected: (_) {},
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      set(() => selected = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final rect = tester.getRect(find.byType(NavChip).at(2));

      Future<int> redCount() async {
        late int red;
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          red = 0;
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
              if (d.getUint8(i) > 230 &&
                  d.getUint8(i + 1) < 60 &&
                  d.getUint8(i + 2) < 60) {
                red++;
              }
            }
          }
        });
        return red;
      }

      expect(await redCount(), lessThan(15), reason: '選んだ瞬間に、アクセント上の色になった');
      // 水の計算は、1フレームで進める時間に上限が有る為、細かく進める。
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(await redCount(), greaterThan(100), reason: '塗りの後も、アクセント上の色にならない');
    });
  }
}
