import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/theme/popup_surface_colors.dart';
import 'package:daidai/widgets/kinari_surface.dart';

/// 生成りのポップアップは、枠線付きの平らな面ではなく、へこんだ面（既読のポップアップと同じ、
/// 2026-11-27）。他のデザインは変えない。
void main() {
  testWidgets('生成りは、へこんだ面の装飾。他は、これまでどおりの箱', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    for (final style in AppUiStyle.values) {
      final decoration = popupCardDecoration(context, Brightness.light, style);
      if (style == AppUiStyle.kinari) {
        expect(decoration, isA<KinariInsetDecoration>());
      } else {
        expect(decoration, isA<BoxDecoration>());
      }
    }
  });

  testWidgets('へこんだ面を、背景に描ける（大きさと角丸を指定できる）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Container(
            width: 120,
            height: 60,
            decoration: const KinariInsetDecoration(
              color: Color(0xFFE6DFD0),
              radius: 12,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Container)), const Size(120, 60));
  });
}
