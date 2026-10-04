import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:flutter/foundation.dart';
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
    required this.onRowHandleDragStart,
    required this.onRowHandleDragUpdate,
    required this.onRowHandleDragEnd,
    required this.onRowHandleDragCancel,
    required this.rowDragIndexNotifier,
    required this.rowDragOffsetNotifier,
    this.menuBuilder,
  });

  final TableNode tableNode;
  final EditorState editorState;
  final TableBlockComponentMenuBuilder? menuBuilder;

  // 行の並び替えドラッグ（2026-09-28追加、ユーザー指示）。座標計算・確定
  // 処理は`table_view.dart`側に集約し、ここでは行インデックスを束縛して
  // 中継するだけ。
  final void Function(int rowIdx, DragStartDetails details)
      onRowHandleDragStart;
  final void Function(int rowIdx, DragUpdateDetails details)
      onRowHandleDragUpdate;
  final void Function(int rowIdx, DragEndDetails details) onRowHandleDragEnd;
  final void Function(int rowIdx) onRowHandleDragCancel;

  // ドラッグ中の行がポインターに追従して見えるようにするための共有notifier
  // （2026-09-28追加、ユーザー指示）。
  final ValueListenable<int?> rowDragIndexNotifier;
  final ValueListenable<double> rowDragOffsetNotifier;

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
          onDragStart: (details) => onRowHandleDragStart(i, details),
          onDragUpdate: (details) => onRowHandleDragUpdate(i, details),
          onDragEnd: (details) => onRowHandleDragEnd(i, details),
          onDragCancel: () => onRowHandleDragCancel(i),
          dragIndexNotifier: rowDragIndexNotifier,
          dragOffsetNotifier: rowDragOffsetNotifier,
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
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.dragIndexNotifier,
    required this.dragOffsetNotifier,
    this.menuBuilder,
  });

  final TableNode tableNode;
  final EditorState editorState;
  final int rowIdx;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragCancelCallback onDragCancel;
  final ValueListenable<int?> dragIndexNotifier;
  final ValueListenable<double> dragOffsetNotifier;

  @override
  State<_RowHandleCell> createState() => _RowHandleCellState();
}

class _RowHandleCellState extends State<_RowHandleCell> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: widget.dragIndexNotifier,
      builder: (context, dragIndex, child) {
        return ValueListenableBuilder<double>(
          valueListenable: widget.dragOffsetNotifier,
          builder: (context, offset, child) {
            // 常に同じ構造（IgnorePointer→Transform.translate）を維持し、
            // 値だけを切り替える（2026-09-28修正、ユーザー指摘: ハイライト
            // 機能追加で並び替えドラッグがまた効かなくなった不具合。構造を
            // 条件分岐で変えると、その位置のElementの型が変わり進行中の
            // GestureDetectorを含むサブツリーが破棄・再構築されてしまう）。
            final isDragging = dragIndex == widget.rowIdx;
            return IgnorePointer(
              ignoring: isDragging,
              child: Transform.translate(
                offset: Offset(0, isDragging ? offset : 0),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      child: SizedBox(
        height: widget.tableNode.getRowHeight(widget.rowIdx),
        child: MouseRegion(
          cursor:
              _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
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
            onHandleDragStart: (details) {
              setState(() => _dragging = true);
              widget.onDragStart(details);
            },
            onHandleDragUpdate: widget.onDragUpdate,
            onHandleDragEnd: (details) {
              setState(() => _dragging = false);
              widget.onDragEnd(details);
            },
            onHandleDragCancel: () {
              setState(() => _dragging = false);
              widget.onDragCancel();
            },
          ),
        ),
      ),
    );
  }
}
