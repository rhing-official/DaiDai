import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 並び替えハンドル（列は上端・行は左端）を表示するために実際に確保する
// ガターの大きさ。以前はマイナス座標へ`transform`ではみ出させていたが、
// Flutterの`RenderBox.hitTest`は祖先ウィジェット自身の実サイズ（0以上の
// 座標範囲）に収まらない位置を子へ渡さないため、列幅次第でハンドルが
// 当たらない/表示されない不具合があった（2026-09-27修正、ユーザー指摘）。
// このガターの分だけ実際にレイアウト上の余白を確保することで、当たり判定を
// 確実にする。
const double kTableHandleGutterSize = 28.0;

// 表の左端に沿った、行の並び替えハンドル専用の実幅ガター（`table_view.dart`
// の列のRowの先頭に追加する）。列ハンドル用ガターと高さを揃えるため、
// 先頭に同じ高さの空白を置く。
class TableRowHandleGutter extends StatelessWidget {
  const TableRowHandleGutter({
    super.key,
    required this.tableNode,
    required this.editorState,
    this.menuBuilder,
  });

  final TableNode tableNode;
  final EditorState editorState;
  final TableBlockComponentMenuBuilder? menuBuilder;

  @override
  Widget build(BuildContext context) {
    final colsHeight = context.select(
      (Node n) => n.attributes[TableBlockKeys.colsHeight] as double? ?? 0.0,
    );
    final rowsLen = tableNode.rowsLen;
    final borderWidth = tableNode.config.borderWidth;

    Widget buildSpacer({bool thick = false}) => SizedBox(
          height: thick ? borderWidth * 2 : borderWidth,
        );

    final rows = <Widget>[buildSpacer()];
    for (var i = 0; i < rowsLen; i++) {
      rows.addAll([
        _RowHandleCell(
          tableNode: tableNode,
          editorState: editorState,
          rowIdx: i,
          menuBuilder: menuBuilder,
        ),
        buildSpacer(thick: i == 0),
      ]);
    }

    return SizedBox(
      width: kTableHandleGutterSize,
      height: kTableHandleGutterSize + colsHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: kTableHandleGutterSize),
          ...rows,
        ],
      ),
    );
  }
}

class _RowHandleCell extends StatefulWidget {
  const _RowHandleCell({
    required this.tableNode,
    required this.editorState,
    required this.rowIdx,
    this.menuBuilder,
  });

  final TableNode tableNode;
  final EditorState editorState;
  final int rowIdx;
  final TableBlockComponentMenuBuilder? menuBuilder;

  @override
  State<_RowHandleCell> createState() => _RowHandleCellState();
}

class _RowHandleCellState extends State<_RowHandleCell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.tableNode.getRowHeight(widget.rowIdx),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: TableActionHandler(
          visible: _hovering,
          node: widget.tableNode.node,
          editorState: widget.editorState,
          position: widget.rowIdx,
          alignment: Alignment.center,
          transform: Matrix4.identity(),
          menuBuilder: widget.menuBuilder,
          dir: TableDirection.row,
        ),
      ),
    );
  }
}
