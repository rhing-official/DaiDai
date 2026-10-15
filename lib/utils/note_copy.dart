import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

import 'note_markdown_parsers.dart';

/// 選択に表ブロックが関わるとき、その選択をMarkdownにして返す。関わらなければ
/// null（通常のコピーに任せる）。標準のコピーは選択範囲の文字を改行で連結する
/// だけで、表のセルが改行区切りの文字列になり、Obsidianなどへ貼っても表に
/// ならない。
String? selectionToMarkdownIfTable(EditorState editorState) {
  final selection = editorState.selection?.normalized;
  if (selection == null || selection.isCollapsed) return null;

  // 選択が及ぶトップレベルのブロックの範囲（表の中の選択はその表1つ）。
  // `getSelectedNodes`は複製したノードを返し親を辿れないため、実際の
  // 文書のパスの先頭（トップレベルの位置）で範囲を求める。
  final children = editorState.document.root.children.toList();
  final first = selection.start.path.first;
  final last = selection.end.path.first;
  if (first < 0 || last >= children.length || first > last) return null;
  final blocks = children.sublist(first, last + 1);
  if (!blocks.any((n) => n.type == TableBlockKeys.type)) return null;

  return documentToMarkdown(
    Document(root: pageNode(children: blocks.map((n) => n.copyWith()))),
    customParsers: noteMarkdownCustomParsers,
  );
}

/// 標準のコピー（Ctrl+C）に、表を含む選択をMarkdownの表で書き出す分岐を足した
/// もの。それ以外は標準と同じ。
final CommandShortcutEvent noteCopyCommand = CommandShortcutEvent(
  key: copyCommand.key,
  getDescription: () => AppFlowyEditorL10n.current.cmdCopySelection,
  command: 'ctrl+c',
  macOSCommand: 'cmd+c',
  handler: (editorState) {
    final markdown = selectionToMarkdownIfTable(editorState);
    if (markdown == null) return copyCommand.handler(editorState);
    AppFlowyClipboard.setData(text: markdown);
    return KeyEventResult.handled;
  },
);
