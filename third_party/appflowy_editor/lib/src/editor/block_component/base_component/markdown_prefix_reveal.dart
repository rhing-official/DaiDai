import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 見出し（`# `）・箇条書き（`- `/`* `）に変換した後も、`#`/`-`の記号を
/// 削除せずノードのテキストに残しておき（[markdownPrefixLength]属性）、
/// 描画側でカーソルがその行に無い間だけ見た目上隠すためのヘルパー
/// （2026-09-26追加、DaiDai側の対応。Obsidianの「ライブプレビュー」を
/// 参考にした、常に生のMarkdownテキストを保持する編集モデル）。
///
/// [textSpan]は各ブロックの`textSpanDecorator`が組み立てた、見出し/
/// 箇条書きの装飾（フォントサイズ・太さ等）を既に適用し終えた後のスパン
/// ツリー。その最初の子（先頭のdelta run）の先頭[prefixLength]文字だけを
/// 切り出し、[isFocused]に応じて別スタイルを当てる。
///
/// - [isFocused]がfalse: ほぼ透明・極小フォントにする（レイアウト上は
///   残るためカーソル位置・Backspaceのオフセット計算は影響を受けない、
///   `appflowy_rich_text.dart`の`autoComplete`属性が使う手法と同じ）。
/// - [isFocused]がtrue: 見出し/箇条書きの装飾を外し、地の文字と同じ
///   目立たない見た目にする（生のMarkdown記法がそこにあると分かる表示）。
TextSpan hideMarkdownPrefixWhenNotFocused({
  required TextSpan textSpan,
  required int? prefixLength,
  required bool isFocused,
  bool omitPrefixWhenHidden = false,
}) {
  if (prefixLength == null || prefixLength <= 0) {
    return textSpan;
  }
  final children = textSpan.children;
  if (children == null || children.isEmpty) {
    return textSpan;
  }
  final first = children.first;
  if (first is! TextSpan || first.text == null) {
    return textSpan;
  }
  final text = first.text!;
  if (text.length < prefixLength) {
    return textSpan;
  }
  final restText = text.substring(prefixLength);
  // 箇条書きは非フォーカス時、記号アイコン（●等）を別途表示するため、
  // 隠したプレフィックスの分だけ余分な幅を予約してしまうと（色を透明にする
  // だけでは幅は残るため）、Enterで追加された2行目以降（`markdownPrefixLength`
  // 属性を持たない）との間でインデントの不一致が生じる（2026-09-27修正）。
  // 箇条書きの呼び出し元だけ`omitPrefixWhenHidden: true`を渡し、非フォーカス時は
  // プレフィックスのテキストラン自体を無くして幅を予約しないようにする。
  if (!isFocused && omitPrefixWhenHidden) {
    final restSpan =
        restText.isEmpty ? null : TextSpan(text: restText, style: first.style);
    return TextSpan(
      children: [if (restSpan != null) restSpan, ...children.skip(1)],
    );
  }
  final baseStyle = first.style ?? const TextStyle();
  // フォントサイズ/太さは`baseStyle`から変えず、色のみで隠す/薄く見せるを
  // 切り替える（2026-09-27修正）。以前は非フォーカス時`fontSize: 0.01`・
  // フォーカス時`fontSize: 16`固定にしていたが、隣接ランのフォントサイズが
  // 大きく異なると`RenderParagraph.getBoxesForSelection`が縮退した矩形を
  // 返すことがあり、`SelectionAreaPainter`側の幅0矩形の救済フォールバック
  // （幅8pxの矩形を強制描画）が本来隠れているはずの位置に本文の文字と重なって
  // 表示され、選択時に文字が二重に見える不具合の原因になっていた。同じ
  // パッケージのオートコンプリート機能が使う`transparent`属性
  // （`appflowy_rich_text.dart`）と同じ「色のみで隠す」手法に揃えることで
  // この不一致を無くす。
  final prefixStyle = isFocused
      ? baseStyle.copyWith(color: baseStyle.color?.withValues(alpha: 0.5))
      : baseStyle.copyWith(color: Colors.transparent);
  final prefixSpan = TextSpan(
    text: text.substring(0, prefixLength),
    style: prefixStyle,
  );
  final restSpan =
      restText.isEmpty ? null : TextSpan(text: restText, style: first.style);
  return TextSpan(
    children: [prefixSpan, if (restSpan != null) restSpan, ...children.skip(1)],
  );
}

/// 見出しボタン・「/」選択メニュー等、`# `/`- `入力によるMarkdownショート
/// カットを経由しない変換経路でも、[hideMarkdownPrefixWhenNotFocused]が扱える
/// プレフィックス付きdeltaを組み立てるための共通ヘルパー（2026-09-27追加）。
///
/// 既に[existingMarkdownPrefixLength]が設定されている場合（例: 見出し
/// レベルをH1→H2に変更するボタン操作）は、まず既存の記号部分を取り除いてから
/// 新しい記号を付け直す（レベル変更のたびに記号が積み重なるのを防ぐ）。
({Delta delta, int markdownPrefixLength}) applyMarkdownPrefix({
  required Delta existingDelta,
  required int? existingMarkdownPrefixLength,
  required String prefix,
}) {
  final body =
      (existingMarkdownPrefixLength != null && existingMarkdownPrefixLength > 0)
          ? existingDelta.slice(existingMarkdownPrefixLength)
          : existingDelta;
  final delta = (Delta()..insert(prefix)) + body;
  return (delta: delta, markdownPrefixLength: prefix.length);
}
