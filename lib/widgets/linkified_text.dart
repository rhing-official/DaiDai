import 'invite_link_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/link_detection.dart';

/// 絵文字（カラーの絵文字として描かれるもの）1つ。ZWJ・肌の色・旗・キーキャップの並びも1つにまとめる。
/// 文字として描かれる記号（`©`・`™`、異体字選択子の無い`☺`など）は含めない。
final RegExp _emojiPattern = RegExp(
  // ignore: valid_regexps
  r'(?:\p{Regional_Indicator}{2}|[0-9#*]\uFE0F?\u20E3|\p{Emoji_Presentation}|\p{Extended_Pictographic}\uFE0F)'
  r'(?:[\u{1F3FB}-\u{1F3FF}]|\uFE0F|[\u{E0020}-\u{E007F}]|\u200D(?:\p{Emoji_Presentation}|\p{Extended_Pictographic})\uFE0F?)*',
  unicode: true,
);

/// 絵文字を描く為のフォント。選んでいる日本語フォントが、絵文字と同じ文字（`❤`など）の白黒の
/// 字形を持っていると、カラーの絵文字ではなく、その簡略な字形で描かれる。絵文字の部分だけ、
/// 絵文字のフォントを指定して、そのまま表示する（2026-11-27）。
String get _emojiFontFamily => kIsWeb
    ? 'Noto Color Emoji'
    : switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
        TargetPlatform.windows => 'Segoe UI Emoji',
        _ => 'Noto Color Emoji',
      };

/// [text]を、絵文字の部分だけ絵文字のフォントにした[TextSpan]に分ける。絵文字が無ければ、
/// 単一の[TextSpan]。文字列の中身（文字数・位置）は変えない。
List<InlineSpan> emojiSpans(String text, TextStyle? style) {
  final matches = _emojiPattern.allMatches(text).toList();
  if (matches.isEmpty) return [TextSpan(text: text, style: style)];
  final emojiStyle = (style ?? const TextStyle()).copyWith(
    fontFamily: _emojiFontFamily,
    fontFamilyFallback: const [
      'Noto Color Emoji',
      'Apple Color Emoji',
      'Segoe UI Emoji',
    ],
  );
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    spans.add(TextSpan(text: m.group(0), style: emojiStyle));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}

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
  Map<String, (Color background, Color color)> mentionLabelHighlights =
      const {},
}) {
  final matches = urlPattern.allMatches(text);
  List<InlineSpan> plain(String segment) => _splitMentions(
    segment,
    style: style,
    labels: mentionLabels,
    color: mentionColor,
    background: mentionBackground,
    labelColors: mentionLabelColors,
    highlights: mentionLabelHighlights,
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
  required Map<String, (Color background, Color color)> highlights,
}) {
  if (labels.isEmpty) return emojiSpans(segment, style);
  // 「@新」と「@新田」のように前方が重なる場合に長い方を優先する。
  final sorted = [...labels]..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(sorted.map(RegExp.escape).join('|'));
  final matches = pattern.allMatches(segment);
  if (matches.isEmpty) return emojiSpans(segment, style);

  final mentionStyle = (style ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w700,
    color: color,
    backgroundColor: background,
  );
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.addAll(emojiSpans(segment.substring(last, m.start), style));
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
            : highlights.containsKey(text)
            // 宛先のロールの色のハイライト（2026-11-16）。
            ? mentionStyle.copyWith(
                color: highlights[text]!.$2,
                backgroundColor: highlights[text]!.$1,
              )
            : mentionStyle,
      ),
    );
    last = m.end;
  }
  if (last < segment.length) {
    spans.addAll(emojiSpans(segment.substring(last), style));
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
    this.mentionLabelHighlights = const {},
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

  /// 宛先ごとのハイライト（`@…`→背景色・文字色、2026-11-16）。ここに無いメンションは
  /// [mentionBackground]・[mentionColor]（見る人のアクセント）。
  final Map<String, (Color background, Color color)> mentionLabelHighlights;

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
    // DaiDai自身の招待リンクは、画面を切り替えずにポップアップで開く（2026-11-09）。
    if (await openInviteLinkDialog(context, url)) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final matches = urlPattern.allMatches(widget.text);
    if (matches.isEmpty && widget.mentionLabels.isEmpty) {
      final plain = emojiSpans(widget.text, widget.style);
      return plain.length == 1
          ? Text(widget.text, style: widget.style)
          : Text.rich(TextSpan(style: widget.style, children: plain));
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
      mentionLabelHighlights: widget.mentionLabelHighlights,
    );

    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
