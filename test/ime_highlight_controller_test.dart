import 'package:daidai/widgets/ime_highlight_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<TextSpan>> _spans(
  WidgetTester tester,
  ImeHighlightController controller,
) async {
  late TextSpan span;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(primary: Colors.red),
      ),
      home: Builder(
        builder: (context) {
          span = controller.buildTextSpan(
            context: context,
            style: const TextStyle(fontSize: 14),
            withComposing: true,
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return span.children!.cast<TextSpan>();
}

void main() {
  testWidgets('変換中でなければ、ラベルを付けない', (tester) async {
    final c = ImeHighlightController()
      ..value = const TextEditingValue(
        text: 'あいうえお',
        selection: TextSelection.collapsed(offset: 5),
      );
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = c.buildTextSpan(context: context, withComposing: true);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      span.children?.any((s) => s.style?.backgroundColor != null) ?? false,
      isFalse,
    );
  });

  testWidgets('変換中は、カーソルまでを濃く、残りを薄く、アクセントカラーで描く', (tester) async {
    final c = ImeHighlightController()
      ..value = const TextEditingValue(
        text: 'あいうえお',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 5),
      );
    final spans = await _spans(tester, c);
    expect(spans.map((s) => s.text), ['あい', 'うえお']);
    final dark = spans[0].style!.backgroundColor!;
    final light = spans[1].style!.backgroundColor!;
    expect(dark.a, greaterThan(light.a));
    expect(dark.r, Colors.red.r);
    expect(spans[0].style!.decoration, TextDecoration.underline);
  });

  testWidgets('キーボードから届いた範囲があれば、それを使う', (tester) async {
    final c = ImeHighlightController()
      ..value = const TextEditingValue(
        text: 'あいうえお',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      )
      ..setHighlights(const [
        ImeHighlight(0, 3, Color(0x664DB6AC)),
        ImeHighlight(3, 5, Color(0x194DB6AC)),
      ]);
    final spans = await _spans(tester, c);
    expect(spans.map((s) => s.text), ['あいう', 'えお']);
  });
}
