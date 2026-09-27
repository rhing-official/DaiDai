import 'package:appflowy_editor/appflowy_editor.dart';

void insertHeadingAfterSelection(EditorState editorState, int level) {
  // 「/」メニューから作る見出しも、`# `入力による変換と同じように先頭記号を
  // 保持する（2026-09-27修正、DaiDai側の対応）。
  final prefix = '${'#' * level} ';
  insertNodeAfterSelection(
    editorState,
    headingNode(
      level: level,
      delta: Delta()..insert(prefix),
      attributes: {HeadingBlockKeys.markdownPrefixLength: prefix.length},
    ),
    cursorOffset: prefix.length,
  );
}

void insertQuoteAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    quoteNode(),
  );
}

void insertCheckboxAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    todoListNode(checked: false),
  );
}

void insertBulletedListAfterSelection(EditorState editorState) {
  // 「/」メニューから作る箇条書きも、`- `入力による変換と同じように先頭記号を
  // 保持する（2026-09-27修正、DaiDai側の対応）。
  const prefix = '- ';
  insertNodeAfterSelection(
    editorState,
    bulletedListNode(
      delta: Delta()..insert(prefix),
      attributes: {BulletedListBlockKeys.markdownPrefixLength: prefix.length},
    ),
    cursorOffset: prefix.length,
  );
}

void insertNumberedListAfterSelection(EditorState editorState) {
  insertNodeAfterSelection(
    editorState,
    numberedListNode(),
  );
}

bool insertNodeAfterSelection(
  EditorState editorState,
  Node node, {
  int cursorOffset = 0,
}) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return false;
  }

  final currentNode = editorState.getNodeAtPath(selection.end.path);
  if (currentNode == null) {
    return false;
  }
  node.updateAttributes({
    blockComponentTextDirection:
        currentNode.attributes[blockComponentTextDirection],
  });

  final transaction = editorState.transaction;
  final delta = currentNode.delta;
  if (delta != null && delta.isEmpty) {
    transaction
      ..insertNode(selection.end.path, node)
      ..deleteNode(currentNode)
      ..afterSelection = Selection.collapsed(
        Position(path: selection.end.path, offset: cursorOffset),
      );
  } else {
    final next = selection.end.path.next;
    transaction
      ..insertNode(next, node)
      ..afterSelection =
          Selection.collapsed(Position(path: next, offset: cursorOffset));
  }

  editorState.apply(transaction);
  return true;
}
