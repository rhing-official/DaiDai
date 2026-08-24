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
}) {
  final matches = urlPattern.allMatches(text);
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
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
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    final url = match.group(0)!;
    final recognizer = TapGestureRecognizer()..onTap = () => onTapUrl(url);
    recognizerSink.add(recognizer);
    spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
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
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

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
    if (matches.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    _disposeRecognizers();
    final spans = buildLinkifiedSpans(
      text: widget.text,
      style: widget.style,
      linkColor: widget.linkColor,
      recognizerSink: _recognizers,
      onTapUrl: _openLink,
    );

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
