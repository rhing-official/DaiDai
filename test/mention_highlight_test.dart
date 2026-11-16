import 'package:daidai/widgets/linkified_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextSpan _span(List<InlineSpan> spans, String text) =>
    spans.whereType<TextSpan>().firstWhere((s) => s.text == text);

void main() {
  List<InlineSpan> build(Map<String, (Color, Color)> highlights) =>
      buildLinkifiedSpans(
        text: 'こんにちは @新田 と @佐藤 と @ロール',
        style: null,
        linkColor: Colors.blue,
        recognizerSink: [],
        onTapUrl: (_) async {},
        mentionLabels: const ['@新田', '@佐藤', '@ロール'],
        mentionColor: Colors.white,
        mentionBackground: Colors.indigo,
        mentionLabelColors: const {'@ロール': Colors.green},
        mentionLabelHighlights: highlights,
      );

  test('宛先のロールの色があるメンションだけ、その色のハイライトになる', () {
    final spans = build({'@新田': (Colors.red, Colors.black)});
    final nitta = _span(spans, '@新田').style!;
    expect(nitta.backgroundColor, Colors.red);
    expect(nitta.color, Colors.black);
    // 色が無い宛先は、見る人のアクセントのまま。
    final sato = _span(spans, '@佐藤').style!;
    expect(sato.backgroundColor, Colors.indigo);
    expect(sato.color, Colors.white);
  });

  test('ロール宛は、文字色だけでハイライトは付かない（従来どおり）', () {
    final role = _span(build({}), '@ロール').style!;
    expect(role.color, Colors.green);
    expect(role.backgroundColor, isNull);
  });
}
