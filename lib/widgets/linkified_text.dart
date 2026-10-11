import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/link_detection.dart';

/// [text]内のURLをタップ可能なリンクとして装飾した[InlineSpan]リストを作る。
/// URLが見つからない場合は単一の[TextSpan]（styleのみ）を返す。
/// [recognizerSink]には生成した[TapGestureRecognizer]を全て追加するので、
/// 呼び出し側は不要になったタイミングで必ずdisposeすること（リーク防止）。
/// `LinkifiedText`と`LinkifiedEditingController`の両方から共有する
/// （2026-08-24切り出し、部分コピーのTextField化に伴う）。
List<InlineSpan> buildLinkifiedSpans({
  required String text,
  required TextStyle? style,
  required Color linkColor,
  required List<TapGestureRecognizer> recognizerSink,
  required Future<void> Function(String url) onTapUrl,
  List<String> mentionLabels = const [],
  Color? mentionColor,
  Color? mentionBackground,
  Map<String, Color?> mentionLabelColors = const {},
}) {
  final matches = urlPattern.allMatches(text);
  List<InlineSpan> plain(String segment) => _splitMentions(
    segment,
    style: style,
    labels: mentionLabels,
    color: mentionColor,
    background: mentionBackground,
    labelColors: mentionLabelColors,
  );
  if (matches.isEmpty) {
    return plain(text);
  }

  final linkStyle = (style ?? const TextStyle()).copyWith(
    color: linkColor,
    decoration: TextDecoration.underline,
    decorationColor: linkColor,
  );

  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in matches) {
    if (match.start > lastEnd) {
      spans.addAll(plain(text.substring(lastEnd, match.start)));
    }
    final url = match.group(0)!;
    final recognizer = TapGestureRecognizer()..onTap = () => onTapUrl(url);
    recognizerSink.add(recognizer);
    spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.addAll(plain(text.substring(lastEnd)));
  }
  return spans;
}

/// [segment]内の`@メンション`（[labels]に一致する箇所）を太字＋色付き
/// （[background]があれば背景も付ける、自分宛のメンション用）にする
/// （2026-10-11追加）。[labels]が空なら単一の[TextSpan]を返す。
List<InlineSpan> _splitMentions(
  String segment, {
  required TextStyle? style,
  required List<String> labels,
  required Color? color,
  required Color? background,
  required Map<String, Color?> labelColors,
}) {
  if (labels.isEmpty) return [TextSpan(text: segment, style: style)];
  // 「@新」と「@新田」のように前方が重なる場合に長い方を優先する。
  final sorted = [...labels]..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(sorted.map(RegExp.escape).join('|'));
  final matches = pattern.allMatches(segment);
  if (matches.isEmpty) return [TextSpan(text: segment, style: style)];

  final mentionStyle = (style ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w700,
    color: color,
    backgroundColor: background,
  );
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.add(TextSpan(text: segment.substring(last, m.start)));
    }
    final text = m.group(0)!;
    // ロール宛はロール自身の色を文字色にするだけ（ハイライトは入れない）。
    spans.add(
      TextSpan(
        text: text,
        style: labelColors.containsKey(text)
            ? (style ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.w700,
                color: labelColors[text],
              )
            : mentionStyle,
      ),
    );
    last = m.end;
  }
  if (last < segment.length) {
    spans.add(TextSpan(text: segment.substring(last)));
  }
  return spans;
}

/// 本文中のURLをタップ可能なリンクとして表示する。それ以外の部分は通常の
/// `Text`と同じスタイルで表示する（メッセージ本文にURLを含めても、これまで
/// タップしてブラウザで開く手段が無かったため導入した）。
///
/// `TapGestureRecognizer`はタップ判定を独自に持つため、確実にdisposeしないと
/// リークする。StatefulWidgetでリストを保持し、本文が変わるたびに作り直す。
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    required this.style,
    required this.linkColor,
    this.mentionLabels = const [],
    this.mentionColor,
    this.mentionBackground,
    this.mentionLabelColors = const {},
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

  /// 本文中で`@メンション`として装飾する文字列（`@`込み、2026-10-11追加）。
  final List<String> mentionLabels;
  final Color? mentionColor;

  /// 自分宛のメンションの時だけ渡す背景色。
  final Color? mentionBackground;

  /// ロール宛メンション（ハイライト無し・ロール色の文字）の`@…`→色。
  final Map<String, Color?> mentionLabelColors;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final matches = urlPattern.allMatches(widget.text);
    if (matches.isEmpty && widget.mentionLabels.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    _disposeRecognizers();
    final spans = buildLinkifiedSpans(
      text: widget.text,
      style: widget.style,
      linkColor: widget.linkColor,
      recognizerSink: _recognizers,
      onTapUrl: _openLink,
      mentionLabels: widget.mentionLabels,
      mentionColor: widget.mentionColor,
      mentionBackground: widget.mentionBackground,
      mentionLabelColors: widget.mentionLabelColors,
    );

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
