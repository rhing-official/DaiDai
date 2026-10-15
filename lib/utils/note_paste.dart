import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../features/note/blocks/table_of_contents_block.dart';
import 'paste_event/paste_event.dart';

final _headingLine = RegExp(r'^#{1,6}\s', multiLine: true);
final _bulletLine = RegExp(r'^\s*[-*+]\s', multiLine: true);
// 表の区切り行（`|---|:--:|` や `--- | ---`）。
final _tableSeparatorLine = RegExp(
  r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$',
  multiLine: true,
);

// 目次の独自ブロック（`note_markdown_parsers.dart`が書き出す）。中身が空の
// コードブロックはMarkdownの解析で捨てられるため、解析の前に目印の行へ
// 置き換え、解析後に目次ブロックへ戻す。
final _tocFence = RegExp(
  r'^```daidai-toc[^\n]*\n(?:[\s\S]*?\n)?```[ \t]*$',
  multiLine: true,
);
const _tocPlaceholder = 'DAIDAITOCBLOCKPLACEHOLDER';

/// Markdownをノートのブロックへ変換する（` ```daidai-toc `は目次ブロックに戻す）。
List<Node> markdownToNoteNodes(String text) {
  final replaced = text.replaceAllMapped(
    _tocFence,
    (_) => '\n$_tocPlaceholder\n',
  );
  final nodes = markdownToDocument(replaced).root.children.toList();
  return [
    for (final n in nodes)
      if (n.type == ParagraphBlockKeys.type &&
          n.delta?.toPlainText().trim() == _tocPlaceholder)
        tableOfContentsNode()
      else if (n.type == TableBlockKeys.type)
        _withColsHeight(n)
      else
        n,
  ];
}

/// Markdownから作った表には、描画が前提にする`colsHeight`（表の高さ）が無く、
/// 貼り付けた直後に`null is not a subtype of num`で表が赤いエラー表示になる。
/// 描画前に、行の高さから算出して入れる。
Node _withColsHeight(Node table) {
  table.updateAttributes({
    TableBlockKeys.colsHeight: TableNode(node: table).colsHeight,
  });
  return table;
}

/// 複数行で、見出し・箇条書き・表・目次の行を含むテキストか。
/// 標準の貼り付けは複数行を全て素の段落にするため、`# 見出し`が文字のまま残る。
/// このようなテキストはMarkdownとして解析して貼る。
bool looksLikeMarkdownBlocks(String text) {
  if (!text.contains('\n')) return false;
  return _headingLine.hasMatch(text) ||
      _bulletLine.hasMatch(text) ||
      _tableSeparatorLine.hasMatch(text) ||
      _tocFence.hasMatch(text);
}

/// 標準の貼り付け（Ctrl+V）に、Markdownとして貼る分岐を足したもの。
/// Obsidianの編集画面などからコピーした見出し・箇条書き・表を、記号が
/// 文字のまま残らず、ブロックとして貼る。それ以外は1行1段落で貼る。
final CommandShortcutEvent notePasteCommand = CommandShortcutEvent(
  key: pasteCommand.key,
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: (editorState) {
    if (editorState.selection == null) return KeyEventResult.ignored;
    // [NOTE-PASTE]: 「貼り付けできない」原因調査用の一時ログ（原因特定後に削除する）。
    () async {
      try {
        debugPrint(
          '[NOTE-PASTE] handler start selection=${editorState.selection}',
        );
        // クリップボードの読み取りは1回だけにする。標準の`pasteCommand`を
        // 呼び直すと2回読むことになり、ブラウザによっては2回目の読み取りが
        // 拒否・再確認され（Firefoxの「貼り付け」確認など）、何も貼れなくなる。
        // このフォークの`AppFlowyClipboard`はHTMLを返さない（常にnull）ため、
        // 標準のHTML優先の分岐は不要で、プレーンテキストの貼り付けだけでよい。
        // 非同期のクリップボード読み取りは、ブラウザの権限・確認で`paste_fail`に
        // なることがある。`paste`イベントの受信を先に仕掛けておき（キー入力と
        // 同じ同期の区間）、読み取りが失敗したらイベントのテキストを使う。
        final eventText = readPasteEventText();
        String? text = await eventText;
        if (text == null) {
          debugPrint('[NOTE-PASTE] no paste event -> clipboard read');
          try {
            text = (await AppFlowyClipboard.getData()).text;
          } catch (e) {
            debugPrint('[NOTE-PASTE] clipboard read failed: $e');
          }
        }
        text = text?.replaceAll('\r', '');
        debugPrint('[NOTE-PASTE] clipboard text length=${text?.length}');
        if (text == null || text.isEmpty) return;
        if (looksLikeMarkdownBlocks(text)) {
          debugPrint('[NOTE-PASTE] markdown path');
          await pasteMarkdownBlocks(editorState, text);
        } else {
          debugPrint('[NOTE-PASTE] plain path');
          await pastePlainTextBlocks(editorState, text);
        }
        debugPrint('[NOTE-PASTE] done selection=${editorState.selection}');
      } catch (e, st) {
        debugPrint('[NOTE-PASTE] FAILED: $e\n$st');
      }
    }();
    // Webは`ignored`を返し、キー入力の既定動作（ブラウザの貼り付け）を止めない。
    // `handled`だとエンジンが既定動作を止め、`paste`イベントが発生しない。
    return kIsWeb ? KeyEventResult.ignored : KeyEventResult.handled;
  },
);

Future<void> pasteMarkdownBlocks(EditorState editorState, String text) async {
  final nodes = markdownToNoteNodes(text);
  if (nodes.isEmpty) return;
  // 表・目次のようなテキストを持たないブロックで終わるときは、直後に空の段落を
  // 足してカーソルを置く（そのブロックにはカーソルが置けず、続きが書けなくなる
  // のを避ける）。
  final addsTrailing = nodes.last.delta == null;
  if (addsTrailing) nodes.add(paragraphNode());

  // 挿入されるブロック列の先頭の位置（末尾の段落の位置を求めるのに使う）。
  Path? start;
  if (nodes.length == 1) {
    await editorState.pasteSingleLineNode(nodes.first);
  } else if (nodes.first.delta == null) {
    start = await _insertBlocksAtCursor(editorState, nodes);
  } else {
    start = editorState.selection?.normalized.start.path;
    await editorState.pasteMultiLineNodes(nodes);
  }
  if (addsTrailing && start != null) {
    final trailingPath = [
      ...start.sublist(0, start.length - 1),
      start.last + nodes.length - 1,
    ];
    editorState.selection = Selection.collapsed(Position(path: trailingPath));
  }
}

/// 先頭がテキストを持たないブロック（表・目次）のとき、カーソル位置へそのまま
/// 挿入する。カーソルが空の段落なら、その段落を置き換える。挿入したブロック列の
/// 先頭の位置を返す。
Future<Path?> _insertBlocksAtCursor(
  EditorState editorState,
  List<Node> nodes,
) async {
  final selection = await editorState.deleteSelectionIfNeeded();
  if (selection == null) return null;
  final current = editorState.getNodeAtPath(selection.end.path);
  if (current == null) return null;
  final replaces =
      current.type == ParagraphBlockKeys.type &&
      (current.delta?.isEmpty ?? false) &&
      current.children.isEmpty;
  final start = replaces ? current.path : current.path.next;
  final transaction = editorState.transaction;
  if (replaces) {
    transaction
      ..insertNodes(start, nodes)
      ..deleteNode(current);
  } else {
    transaction.insertNodes(start, nodes);
  }
  await editorState.apply(transaction);
  return start;
}

final _wholeUrl = RegExp(r'^https?://\S+$');

/// 記号を含まない普通のテキストを、1行ごとの段落として貼る。行全体がURLなら
/// リンクにする（標準の貼り付けの自動リンクのうち、行全体がURLの場合のみ）。
Future<void> pastePlainTextBlocks(EditorState editorState, String text) async {
  final nodes = text.split('\n').map((line) {
    final trimmed = line.trimRight();
    final delta = Delta()
      ..insert(
        trimmed,
        attributes: _wholeUrl.hasMatch(trimmed)
            ? {AppFlowyRichTextKeys.href: trimmed}
            : null,
      );
    return paragraphNode(delta: delta);
  }).toList();
  if (nodes.length == 1) {
    await editorState.pasteSingleLineNode(nodes.first);
  } else {
    await editorState.pasteMultiLineNodes(nodes);
  }
}
