import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'linkified_text.dart';

/// 部分コピー用の読み取り専用`TextField`に本文を流し込む
/// `TextEditingController`。`buildTextSpan`をoverrideし、
/// [buildLinkifiedSpans]（`linkified_text.dart`と共有）でURLリンクの
/// 見た目・タップを`TextField`上でも再現する（2026-08-24追加、
/// `SelectionArea`ベースの部分コピー実装が選択ハイライトを描画しない
/// 不具合の代替として、`TextField`と同じ`RenderEditable`系の選択機構に
/// 乗り換えた）。
///
/// [linkColor]は呼び出し側（`_MessageRow`）がbuild時に、自分/相手・
/// 劇画スタイルの別に応じて直接代入する（テーマ依存の値をコンストラクタ
/// 時点では持てないため）。
class LinkifiedEditingController extends TextEditingController {
  Color linkColor = Colors.blue;

  final _recognizers = <TapGestureRecognizer>[];

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
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    _disposeRecognizers();
    return TextSpan(
      style: style,
      children: buildLinkifiedSpans(
        text: text,
        style: style,
        linkColor: linkColor,
        recognizerSink: _recognizers,
        onTapUrl: _openLink,
      ),
    );
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }
}
