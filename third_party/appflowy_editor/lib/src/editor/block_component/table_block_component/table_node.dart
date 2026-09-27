import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_config.dart';

class TableNode {
  final TableConfig _config;

  final Node node;
  final List<List<Node>> _cells = [];

  TableNode({
    required this.node,
  }) : _config = TableConfig.fromJson(node.attributes) {
    if (node.type != TableBlockKeys.type) {
      AppFlowyEditorLog.editor.debug('TableNode: node is not a table');
      return;
    }

    final attributes = node.attributes;
    final colsLen = attributes[TableBlockKeys.colsLen];
    final rowsLen = attributes[TableBlockKeys.rowsLen];

    if (colsLen == null ||
        rowsLen == null ||
        colsLen is! int ||
        rowsLen is! int) {
      AppFlowyEditorLog.editor.debug(
        'TableNode: colsLen or rowsLen is not an integer or null',
      );
      return;
    }

    if (node.children.length != colsLen * rowsLen) {
      AppFlowyEditorLog.editor.debug(
        'TableNode: the number of children is not equal to the number of cells',
      );
      return;
    }

    // every cell should has rowPosition and colPosition to indicate its position in the table
    for (final child in node.children) {
      if (!child.attributes.containsKey(TableCellBlockKeys.rowPosition) ||
          !child.attributes.containsKey(TableCellBlockKeys.colPosition)) {
        AppFlowyEditorLog.editor
            .debug('TableNode: cell has no rowPosition or colPosition');
        return;
      }
    }

    for (var i = 0; i < colsLen; i++) {
      _cells.add([]);
      for (var j = 0; j < rowsLen; j++) {
        final cell = node.children
            .where(
              (n) =>
                  n.attributes[TableCellBlockKeys.colPosition] == i &&
                  n.attributes[TableCellBlockKeys.rowPosition] == j,
            )
            .firstOrNull;

        if (cell == null) {
          AppFlowyEditorLog.editor.debug('TableNode: cell is empty');
          _cells.clear();
          return;
        }

        _cells[i].add(newCellNode(node, cell));
      }
    }
  }

  factory TableNode.fromJson(Map<String, Object> json) {
    return TableNode(node: Node.fromJson(json));
  }

  static TableNode fromList<T>(List<List<T>> cols, {TableConfig? config}) {
    assert(
      T == String ||
          (T == Node &&
              cols.every(
                (col) => col.every((n) => (n as Node).delta != null),
              )),
    );
    assert(cols.isNotEmpty);
    assert(cols[0].isNotEmpty);
    assert(cols.every((col) => col.length == cols[0].length));

    config = config ?? TableConfig();

    Node node = Node(
      type: TableBlockKeys.type,
      attributes: {}
        ..addAll({
          TableBlockKeys.colsLen: cols.length,
          TableBlockKeys.rowsLen: cols[0].length,
        })
        ..addAll(config.toJson()),
    );
    for (var i = 0; i < cols.length; i++) {
      for (var j = 0; j < cols[0].length; j++) {
        final cell = Node(
          type: TableCellBlockKeys.type,
          attributes: {
            TableCellBlockKeys.colPosition: i,
            TableCellBlockKeys.rowPosition: j,
          },
        );

        late Node cellChild;
        if (T == String) {
          cellChild = paragraphNode(
            delta: Delta()..insert(cols[i][j] as String),
          );
        } else {
          cellChild = cols[i][j] as Node;
        }
        cell.insert(cellChild);

        node.insert(cell);
      }
    }

    return TableNode(node: node);
  }

  Node getCell(int col, row) => _cells[col][row];

  TableConfig get config => _config;

  int get colsLen => _cells.length;

  int get rowsLen => _cells.isNotEmpty ? _cells[0].length : 0;

  double getRowHeight(int row) =>
      double.tryParse(
        _cells[0][row].attributes[TableCellBlockKeys.height].toString(),
      ) ??
      _config.rowDefaultHeight;

  double get colsHeight =>
      List.generate(rowsLen, (idx) => idx).fold<double>(
        0,
        (prev, cur) => prev + getRowHeight(cur) + _config.borderWidth,
      ) +
      _config.borderWidth +
      // 1行目（見出し行）と2行目の間の罫線だけ太線（borderWidth*2）で
      // 描画される（table_col.dartの_buildCells参照）分を反映する
      // （2026-09-27修正。以前はここが抜けており、この値を実際の高さの
      // 制約として使うガター実装を追加した際に2pxのオーバーフローとして
      // 顕在化した）。
      (rowsLen >= 2 ? _config.borderWidth : 0);

  double getColWidth(int col) =>
      double.tryParse(
        _cells[col][0].attributes[TableCellBlockKeys.width].toString(),
      ) ??
      _config.colDefaultWidth;

  double get tableWidth =>
      List.generate(colsLen, (idx) => idx).fold<double>(
        0,
        (prev, cur) => prev + getColWidth(cur) + _config.borderWidth,
      ) +
      _config.borderWidth;

  // 以下は表の外周ルーラー（列の並び替えハンドル用の上端ルーラー・行の
  // 並び替えハンドル用の左端ルーラー・列幅リサイズの当たり領域）が、
  // ポインター座標から対象の列/行を求めるための補助（2026-09-27追加）。
  // `tableWidth`/`colsHeight`の合計値の式はそのまま変更しない。

  // col番目の列の右側罫線の中心x座標。
  double colDividerCenterX(int col) {
    double x = _config.borderWidth;
    for (var i = 0; i < col; i++) {
      x += getColWidth(i) + _config.borderWidth;
    }
    return x + getColWidth(col) + _config.borderWidth / 2;
  }

  // x座標からその位置が属する列のインデックスを求める。
  int colIndexAtX(double dx) {
    double x = _config.borderWidth;
    for (var i = 0; i < colsLen; i++) {
      final w = getColWidth(i);
      if (dx < x + w + _config.borderWidth || i == colsLen - 1) {
        return i;
      }
      x += w + _config.borderWidth;
    }
    return colsLen - 1;
  }

  // row番目の行の上端y座標。1行目（見出し行）の直後だけ罫線が太い
  // （`table_col.dart`の`_buildCells`参照）ことを反映する。
  double rowTopY(int row) {
    double y = _config.borderWidth;
    for (var i = 0; i < row; i++) {
      y += getRowHeight(i) +
          (i == 0 ? _config.borderWidth * 2 : _config.borderWidth);
    }
    return y;
  }

  // y座標からその位置が属する行のインデックスを求める。
  int rowIndexAtY(double dy) {
    double y = _config.borderWidth;
    for (var i = 0; i < rowsLen; i++) {
      final h = getRowHeight(i);
      final divider = i == 0 ? _config.borderWidth * 2 : _config.borderWidth;
      if (dy < y + h + divider || i == rowsLen - 1) {
        return i;
      }
      y += h + divider;
    }
    return rowsLen - 1;
  }

  void setColWidth(
    int col,
    double w, {
    Transaction? transaction,
    bool force = false,
  }) {
    w = w < _config.colMinimumWidth ? _config.colMinimumWidth : w;
    if (getColWidth(col) != w || force) {
      for (int i = 0; i < rowsLen; i++) {
        if (transaction != null) {
          transaction.updateNode(_cells[col][i], {TableCellBlockKeys.width: w});
        } else {
          _cells[col][i].updateAttributes({TableCellBlockKeys.width: w});
        }
        updateRowHeight(i, transaction: transaction);
      }
      if (transaction != null) {
        transaction.updateNode(node, node.attributes);
      } else {
        node.updateAttributes(node.attributes);
      }
    }
  }

  void updateRowHeight(
    int row, {
    EditorState? editorState,
    Transaction? transaction,
  }) {
    // The extra 8 is because of paragraph padding
    double maxHeight = _cells
        .map<double>((c) => c[row].children.first.rect.height + 8)
        .reduce(max);

    if (_cells[0][row].attributes[TableCellBlockKeys.height] != maxHeight &&
        !maxHeight.isNaN) {
      for (int i = 0; i < colsLen; i++) {
        final currHeight = _cells[i][row].attributes[TableCellBlockKeys.height];
        if (currHeight == maxHeight) {
          continue;
        }

        if (transaction != null) {
          transaction.updateNode(
            _cells[i][row],
            {TableCellBlockKeys.height: maxHeight},
          );
        } else {
          _cells[i][row].updateAttributes(
            {TableCellBlockKeys.height: maxHeight},
          );
        }
      }
    }

    if (node.attributes[TableBlockKeys.colsHeight] != colsHeight &&
        !colsHeight.isNaN) {
      if (transaction != null) {
        transaction.updateNode(node, {TableBlockKeys.colsHeight: colsHeight});
        if (editorState != null && editorState.editable != true) {
          node.updateAttributes({TableBlockKeys.colsHeight: colsHeight});
        }
      } else {
        node.updateAttributes({TableBlockKeys.colsHeight: colsHeight});
      }
    }
  }
}
