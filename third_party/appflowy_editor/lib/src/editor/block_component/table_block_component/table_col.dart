import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col_border.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_handle_gutter.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCol extends StatefulWidget {
  const TableCol({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.tableStyle,
    required this.resizeHoverColNotifier,
    required this.resizeDraggingColNotifier,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.colDragIndexNotifier,
    required this.colDragOffsetNotifier,
    required this.rowDragIndexNotifier,
    required this.rowDragOffsetNotifier,
    this.menuBuilder,
  });

  final int colIdx;
  final EditorState editorState;
  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;

  final TableStyle tableStyle;

  // 列幅リサイズ用の罫線（`table_view.dart`側の当たり領域）がホバー/ドラッグ
  // 中かどうかの共有状態。並び替えハンドルの表示トリガーとは別物
  // （2026-09-27追加）。
  final ValueListenable<int?> resizeHoverColNotifier;
  final ValueListenable<int?> resizeDraggingColNotifier;

  // 列の並び替えドラッグ（2026-09-28追加、ユーザー指示）。座標計算・確定
  // 処理は`table_view.dart`側に集約し、ここではコールバックを中継する。
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragCancelCallback onDragCancel;

  // ドラッグ中の列/行がポインターに追従して見えるようにするための共有
  // notifier（2026-09-28追加、ユーザー指示）。列のドラッグ自身の追従には
  // col側を、行のドラッグ中に自分の列内の該当セルを追従させるにはrow側を
  // 使う（`_buildCells`参照）。
  final ValueListenable<int?> colDragIndexNotifier;
  final ValueListenable<double> colDragOffsetNotifier;
  final ValueListenable<int?> rowDragIndexNotifier;
  final ValueListenable<double> rowDragOffsetNotifier;

  @override
  State<TableCol> createState() => _TableColState();
}

class _TableColState extends State<TableCol> {
  Map<String, void Function()> listeners = {};

  // 列の並び替えハンドルの表示トリガー。以前はマイナスのy座標へ`transform`で
  // はみ出させたハンドルを、表の外周に沿った別ウィジェットのホバーで表示させて
  // いたが、Flutterの`RenderBox.hitTest`はマイナス座標（祖先の実サイズの外側）
  // を子に渡さないため、列幅が広い場合などに当たり判定が不安定だった
  // （2026-09-27修正、ユーザー指摘）。実際にハンドルを描画する場所そのものを
  // 実サイズのガター（`kTableHandleGutterSize`分の高さ）として確保し、その
  // ガター自身のホバーで表示を切り替えるローカルstateに変更した。
  bool _colHandleHovering = false;
  bool _colHandleDragging = false;

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if (widget.colIdx == 0) {
      children.add(
        TableColBorder(
          resizable: false,
          tableNode: widget.tableNode,
          colIdx: widget.colIdx,
          borderColor: widget.tableStyle.borderColor,
          borderHoverColor: widget.tableStyle.borderHoverColor,
        ),
      );
    }

    children.addAll([
      ValueListenableBuilder<int?>(
        valueListenable: widget.colDragIndexNotifier,
        builder: (context, dragIndex, child) {
          return ValueListenableBuilder<double>(
            valueListenable: widget.colDragOffsetNotifier,
            builder: (context, offset, child) {
              // ドラッグ中かどうかで別のウィジェット構造（ラップの有無）を
              // 返すと、その位置のElementの型が変わり、既存のサブツリー
              // （進行中のGestureDetectorを含む）が破棄・再構築されてしまう
              // （2026-09-28修正、ユーザー指摘: ハイライト機能追加で並び替え
              // ドラッグがまた効かなくなった不具合）。ドラッグ中かどうかに
              // 関わらず常に同じ構造（IgnorePointer→Transform.translate）を
              // 維持し、値だけを切り替えることでサブツリーを維持する。
              final isDragging = dragIndex == widget.colIdx;
              return IgnorePointer(
                ignoring: isDragging,
                child: Transform.translate(
                  offset: Offset(isDragging ? offset : 0, 0),
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        child: SizedBox(
          width: context.select(
            (Node n) => getCellNode(n, widget.colIdx, 0)?.cellWidth,
          ),
          height: kTableHandleGutterSize +
              context
                  .select((Node n) => n.attributes[TableBlockKeys.colsHeight]),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: kTableHandleGutterSize,
                child: Column(children: _buildCells(context)),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: kTableHandleGutterSize,
                child: MouseRegion(
                  cursor: _colHandleDragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
                  onEnter: (_) => setState(() => _colHandleHovering = true),
                  onExit: (_) => setState(() => _colHandleHovering = false),
                  child: TableActionHandler(
                    visible: _colHandleHovering,
                    node: widget.tableNode.node,
                    editorState: widget.editorState,
                    position: widget.colIdx,
                    alignment: Alignment.center,
                    transform: Matrix4.identity(),
                    menuBuilder: widget.menuBuilder,
                    dir: TableDirection.col,
                    onHandleDragStart: (details) {
                      setState(() => _colHandleDragging = true);
                      widget.onDragStart(details);
                    },
                    onHandleDragUpdate: widget.onDragUpdate,
                    onHandleDragEnd: (details) {
                      setState(() => _colHandleDragging = false);
                      widget.onDragEnd(details);
                    },
                    onHandleDragCancel: () {
                      setState(() => _colHandleDragging = false);
                      widget.onDragCancel();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ValueListenableBuilder<int?>(
        valueListenable: widget.resizeHoverColNotifier,
        builder: (context, hoverCol, _) => ValueListenableBuilder<int?>(
          valueListenable: widget.resizeDraggingColNotifier,
          builder: (context, dragCol, _) => TableColBorder(
            resizable: true,
            tableNode: widget.tableNode,
            colIdx: widget.colIdx,
            borderColor: widget.tableStyle.borderColor,
            borderHoverColor: widget.tableStyle.borderHoverColor,
            highlighted: hoverCol == widget.colIdx || dragCol == widget.colIdx,
          ),
        ),
      ),
    ]);

    // 罫線（`TableColBorder`、高さ=colsHeightのまま）を、ハンドル用ガター分
    // 伸びたセル列の下側（＝実際の表の内容の高さ）に揃える（2026-09-27追加）。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );
  }

  List<Widget> _buildCells(BuildContext context) {
    final rowsLen = widget.tableNode.rowsLen;
    final List<Widget> cells = [];
    Widget buildCellBorder({bool thick = false}) => Container(
          // 1行目（見出し行）と2行目の間だけ太線にする（2026-09-27追加、
          // ユーザー指示）。
          height: thick
              ? widget.tableNode.config.borderWidth * 2
              : widget.tableNode.config.borderWidth,
          color: widget.tableStyle.borderColor,
        );

    for (var i = 0; i < rowsLen; i++) {
      final node = widget.tableNode.getCell(widget.colIdx, i);
      updateRowHeightCallback(i);
      addListener(node, i);
      addListener(node.children.first, i);

      cells.addAll([
        _buildDragFollowingCell(
          widget.editorState.renderer.build(
            context,
            node,
          ),
          i,
        ),
        buildCellBorder(thick: i == 0),
      ]);
    }

    return [
      buildCellBorder(),
      ...cells,
    ];
  }

  // 行の並び替えドラッグ中、対象行のセルがポインターに追従して見えるように
  // する（2026-09-28追加、ユーザー指示）。行のセル本体は列ごとに分散して
  // 描画されているため、各列でこのラップを行い1行分の見た目を揃える。
  Widget _buildDragFollowingCell(Widget cell, int rowIdx) {
    return ValueListenableBuilder<int?>(
      valueListenable: widget.rowDragIndexNotifier,
      builder: (context, dragIndex, child) {
        return ValueListenableBuilder<double>(
          valueListenable: widget.rowDragOffsetNotifier,
          builder: (context, offset, child) {
            // 常に同じ構造（IgnorePointer→Transform.translate）を維持し、
            // 値だけを切り替える（2026-09-28修正、上のcolDragIndexNotifier
            // 側と同じ理由。構造を条件分岐で変えるとサブツリーが破棄・
            // 再構築され、セル内容の状態が失われうる）。
            final isDragging = dragIndex == rowIdx;
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
      child: cell,
    );
  }

  void addListener(Node node, int row) {
    if (listeners.containsKey(node.id)) {
      return;
    }

    listeners[node.id] = () => updateRowHeightCallback(row);
    node.addListener(listeners[node.id]!);
  }

  void updateRowHeightCallback(int row) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (row >= widget.tableNode.rowsLen) {
          return;
        }

        final transaction = widget.editorState.transaction;
        widget.tableNode.updateRowHeight(
          row,
          editorState: widget.editorState,
          transaction: transaction,
        );
        if (transaction.operations.isNotEmpty) {
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
        }
      });
}
