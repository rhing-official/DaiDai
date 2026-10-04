import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';

class TableActions {
  const TableActions._();

  static void add(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _addCol(node, position, editorState);
    } else {
      _addRow(node, position, editorState);
    }
  }

  static void delete(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _deleteCol(node, position, editorState);
    } else {
      _deleteRow(node, position, editorState);
    }
  }

  /// [position]番目の行/列の全セルを複数セル選択の状態にする（2026-10-04追加、
  /// DaiDai patch。行/列ハンドルのクリックで選択し、Backspace/Deleteで
  /// その行/列を削除できるようにするため。削除そのものは`note_table_delete.dart`
  /// のコマンドが行う）。選択は、行/列の最初のセルの先頭の段落の先頭から
  /// 最後のセルの末尾の段落の末尾まで。
  static void select(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    final key = dir == TableDirection.col
        ? TableCellBlockKeys.colPosition
        : TableCellBlockKeys.rowPosition;
    final otherKey = dir == TableDirection.col
        ? TableCellBlockKeys.rowPosition
        : TableCellBlockKeys.colPosition;
    final cells =
        node.children.where((cell) => cell.attributes[key] == position).toList()
          ..sort(
            (a, b) => (a.attributes[otherKey] as int)
                .compareTo(b.attributes[otherKey] as int),
          );
    if (cells.isEmpty) return;
    Node? firstLeaf(Node n) {
      if (n.delta != null) return n;
      for (final child in n.children) {
        final leaf = firstLeaf(child);
        if (leaf != null) return leaf;
      }
      return null;
    }

    Node? lastLeaf(Node n) {
      if (n.delta != null) return n;
      for (final child in n.children.toList().reversed) {
        final leaf = lastLeaf(child);
        if (leaf != null) return leaf;
      }
      return null;
    }

    final first = firstLeaf(cells.first);
    final last = lastLeaf(cells.last);
    if (first == null || last == null) return;
    editorState.selection = Selection(
      start: Position(path: first.path),
      end: Position(path: last.path, offset: last.delta?.length ?? 0),
    );
  }

  static void duplicate(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _duplicateCol(node, position, editorState);
    } else {
      _duplicateRow(node, position, editorState);
    }
  }

  static void clear(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _clearCol(node, position, editorState);
    } else {
      _clearRow(node, position, editorState);
    }
  }

  static void setBgColor(
    Node node,
    int position,
    EditorState editorState,
    String? color,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _setColBgColor(node, position, editorState, color);
    } else {
      _setRowBgColor(node, position, editorState, color);
    }
  }
}

void _addCol(Node tableNode, int position, EditorState editorState) {
  assert(position >= 0);

  final transaction = editorState.transaction;

  List<Node> cellNodes = [];
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (position != colsLen) {
    for (var i = position; i < colsLen; i++) {
      for (var j = 0; j < rowsLen; j++) {
        final node = getCellNode(tableNode, i, j)!;
        transaction.updateNode(node, {TableCellBlockKeys.colPosition: i + 1});
      }
    }
  }

  for (var i = 0; i < rowsLen; i++) {
    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: position,
        TableCellBlockKeys.rowPosition: i,
      },
    );
    node.insert(paragraphNode());
    final firstCellInRow = getCellNode(tableNode, 0, i);
    if (firstCellInRow?.attributes
            .containsKey(TableCellBlockKeys.rowBackgroundColor) ??
        false) {
      node.updateAttributes({
        TableCellBlockKeys.rowBackgroundColor:
            firstCellInRow!.attributes[TableCellBlockKeys.rowBackgroundColor],
      });
    }

    cellNodes.add(newCellNode(tableNode, node));
  }

  late Path insertPath;
  if (position == 0) {
    insertPath = getCellNode(tableNode, 0, 0)!.path;
  } else {
    insertPath = getCellNode(tableNode, position - 1, rowsLen - 1)!.path.next;
  }
  // TODO(zoli): this calls notifyListener rowsLen+1 times. isn't there a better
  // way?
  transaction.insertNodes(insertPath, cellNodes);
  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

void _addRow(Node tableNode, int position, EditorState editorState) async {
  assert(position >= 0);

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // insert new rows
  var error = false;

  // generate new table cell nodes & update node attributes
  for (var i = 0; i < colsLen; i++) {
    final firstCellInCol = getCellNode(tableNode, i, 0);
    final colBgColor =
        firstCellInCol?.attributes[TableCellBlockKeys.colBackgroundColor];
    final containsColBgColor = colBgColor != null;

    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: i,
        TableCellBlockKeys.rowPosition: position,
        if (containsColBgColor)
          TableCellBlockKeys.colBackgroundColor: colBgColor,
      },
      children: [paragraphNode()],
    );

    late Path insertPath;
    if (position == 0) {
      final firstCellInCol = getCellNode(tableNode, i, 0);
      if (firstCellInCol == null) {
        error = true;
        break;
      }
      insertPath = firstCellInCol.path;
    } else {
      final cellInPrevRow = getCellNode(tableNode, i, position - 1);
      if (cellInPrevRow == null) {
        error = true;
        break;
      }
      insertPath = cellInPrevRow.path.next;
    }

    final transaction = editorState.transaction;

    if (position != rowsLen) {
      for (var j = position; j < rowsLen; j++) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode == null) {
          error = true;
          break;
        }
        transaction.updateNode(
          cellNode,
          {
            TableCellBlockKeys.rowPosition: j + 1,
          },
        );
      }
    }

    transaction.insertNode(insertPath, node);

    await editorState.apply(transaction, withUpdateSelection: false);
  }

  if (error) {
    AppFlowyEditorLog.editor.debug('unable to insert row');
    return;
  }

  final transaction = editorState.transaction;

  // update the row length
  transaction.updateNode(tableNode, {
    TableBlockKeys.rowsLen: rowsLen + 1,
  });

  await editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (colsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < rowsLen; i++) {
      nodes.add(getCellNode(tableNode, col, i)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, editorState, col + 1, 0, -1, 0);

    transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (rowsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < colsLen; i++) {
      nodes.add(getCellNode(tableNode, i, row)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, editorState, 0, row + 1, 0, -1);

    transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  List<Node> nodes = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    nodes.add(
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.colPosition: col + 1,
          TableCellBlockKeys.rowPosition: i,
        },
      ),
    );
  }
  transaction.insertNodes(
    getCellNode(tableNode, col, rowsLen - 1)!.path.next,
    nodes,
  );

  _updateCellPositions(tableNode, editorState, col + 1, 0, 1, 0);

  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateRow(Node tableNode, int row, EditorState editorState) async {
  Transaction transaction = editorState.transaction;
  _updateCellPositions(tableNode, editorState, 0, row + 1, 0, 1);
  await editorState.apply(transaction, withUpdateSelection: false);

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction = editorState.transaction;
    transaction.insertNode(
      node.path.next,
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.rowPosition: row + 1,
          TableCellBlockKeys.colPosition: i,
        },
      ),
    );
    await editorState.apply(transaction, withUpdateSelection: false);
  }

  transaction = editorState.transaction;
  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen + 1});
  editorState.apply(transaction, withUpdateSelection: false);
}

void _setColBgColor(
  Node tableNode,
  int col,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final rowslen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowslen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.updateNode(
      node,
      {TableCellBlockKeys.colBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _setRowBgColor(
  Node tableNode,
  int row,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.updateNode(
      node,
      {TableCellBlockKeys.rowBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearCol(
  Node tableNode,
  int col,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.insertNode(
      node.children.first.path,
      paragraphNode(text: ''),
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearRow(
  Node tableNode,
  int row,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.insertNode(
      node.children.first.path,
      paragraphNode(text: ''),
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

dynamic newCellNode(Node tableNode, n) {
  final row = n.attributes[TableCellBlockKeys.rowPosition] as int;
  final col = n.attributes[TableCellBlockKeys.colPosition] as int;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (!n.attributes.containsKey(TableCellBlockKeys.height)) {
    double nodeHeight = double.tryParse(
      tableNode.attributes[TableBlockKeys.rowDefaultHeight].toString(),
    )!;
    if (row < rowsLen) {
      nodeHeight = double.tryParse(
            getCellNode(tableNode, 0, row)!
                .attributes[TableCellBlockKeys.height]
                .toString(),
          ) ??
          nodeHeight;
    }
    n.updateAttributes({TableCellBlockKeys.height: nodeHeight});
  }

  if (!n.attributes.containsKey(TableCellBlockKeys.width)) {
    double nodeWidth = double.tryParse(
      tableNode.attributes[TableBlockKeys.colDefaultWidth].toString(),
    )!;
    if (col < colsLen) {
      nodeWidth = double.tryParse(
            getCellNode(tableNode, col, 0)!
                .attributes[TableCellBlockKeys.width]
                .toString(),
          ) ??
          nodeWidth;
    }
    n.updateAttributes({TableCellBlockKeys.width: nodeWidth});
  }

  return n;
}

void _updateCellPositions(
  Node tableNode,
  EditorState editorState,
  int fromCol,
  int fromRow,
  int addToCol,
  int addToRow,
) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  for (var i = fromCol; i < colsLen; i++) {
    for (var j = fromRow; j < rowsLen; j++) {
      transaction.updateNode(getCellNode(tableNode, i, j)!, {
        TableCellBlockKeys.colPosition: i + addToCol,
        TableCellBlockKeys.rowPosition: j + addToRow,
      });
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}
