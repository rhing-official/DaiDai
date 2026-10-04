import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_add_button.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_handle_gutter.dart';
import 'package:flutter/material.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
    this.cornerHandleBuilder,
    this.scrollController,
  });

  final Widget Function(BuildContext context, Node node)? cornerHandleBuilder;

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  // 列を追加/リサイズした際、表がノートの表示領域の右端よりはみ出て見えなく
  // ならないよう追従スクロールさせるための、`table_block_component.dart`側の
  // スクロールコントローラ（2026-09-27追加、ユーザー指摘）。
  final ScrollController? scrollController;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  // 列幅リサイズ罫線の当たり領域（本体は見た目のみの`TableColBorder`、
  // 当たり判定は表全体サイズのStackを持つこのウィジェット側に集約している。
  // 2026-09-27、罫線が細すぎて当てにくい問題への対応で導入済み）。
  final ValueNotifier<int?> _resizeHoverCol = ValueNotifier(null);
  final ValueNotifier<int?> _resizeDraggingCol = ValueNotifier(null);

  // 列幅リサイズ中に表の右端を見ていた場合だけ、リサイズに追従して
  // スクロールさせるためのフラグ（2026-09-27追加、ユーザー指摘:
  // 列を広げる/増やすと表の表示領域の右端からはみ出て見えなくなる件）。
  bool _wasAtEndWhenResizeStarted = false;

  // 行/列の並び替えドラッグ用（2026-09-28追加、ユーザー指示）。
  // `table`（Stackの唯一の非Positioned子）は`SingleChildScrollView`の実際の
  // スクロール対象そのものなので、このキー経由の`globalToLocal`はスクロール
  // 位置を考慮した「表コンテンツ内座標」をそのまま返す。
  final GlobalKey _tableContentKey = GlobalKey();
  final ValueNotifier<int?> _colDropIndex = ValueNotifier(null);
  final ValueNotifier<int?> _rowDropIndex = ValueNotifier(null);
  int? _colDragFrom;
  int? _rowDragFrom;

  // ドラッグ中の列/行がポインターに追従して見えるようにするための、
  // 掴んでいる対象のインデックスとドラッグ開始位置からの累積オフセット
  // （2026-09-28追加、ユーザー指示: 紫の枠で囲み実際に追従して動かす）。
  final ValueNotifier<int?> _colDragIndex = ValueNotifier(null);
  final ValueNotifier<double> _colDragOffset = ValueNotifier(0);
  final ValueNotifier<int?> _rowDragIndex = ValueNotifier(null);
  final ValueNotifier<double> _rowDragOffset = ValueNotifier(0);

  @override
  void dispose() {
    _resizeHoverCol.dispose();
    _resizeDraggingCol.dispose();
    _colDropIndex.dispose();
    _rowDropIndex.dispose();
    _colDragIndex.dispose();
    _colDragOffset.dispose();
    _rowDragIndex.dispose();
    _rowDragOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = Row(
      key: _tableContentKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TableRowHandleGutter(
                  tableNode: widget.tableNode,
                  editorState: widget.editorState,
                  menuBuilder: widget.menuBuilder,
                  cornerHandle: widget.cornerHandleBuilder?.call(
                    context,
                    widget.tableNode.node,
                  ),
                  onRowHandleDragStart: _onRowHandleDragStart,
                  onRowHandleDragUpdate: _onRowHandleDragUpdate,
                  onRowHandleDragEnd: _onRowHandleDragEnd,
                  onRowHandleDragCancel: _onRowHandleDragCancel,
                  rowDragIndexNotifier: _rowDragIndex,
                  rowDragOffsetNotifier: _rowDragOffset,
                ),
                ..._buildColumns(context),
                TableActionButton(
                  padding: const EdgeInsets.only(left: 0),
                  icon: widget.tableStyle.addIcon,
                  borderColor: widget.tableStyle.borderColor,
                  width: 28,
                  height: widget.tableNode.colsHeight,
                  onPressed: () {
                    TableActions.add(
                      widget.tableNode.node,
                      widget.tableNode.colsLen,
                      widget.editorState,
                      TableDirection.col,
                    );
                    _scrollToEndAfterLayout();
                  },
                ),
              ],
            ),
            TableActionButton(
              padding: const EdgeInsets.only(top: 1, right: 30),
              icon: widget.tableStyle.addIcon,
              borderColor: widget.tableStyle.borderColor,
              height: 28,
              width: widget.tableNode.tableWidth,
              onPressed: () {
                TableActions.add(
                  widget.tableNode.node,
                  widget.tableNode.rowsLen,
                  widget.editorState,
                  TableDirection.row,
                );
              },
            ),
          ],
        ),
      ],
    );

    return Stack(
      // `table`（非Positioned・唯一の実体）のサイズがこのStack自身の当たり
      // 判定ボックスになる。列幅リサイズの当たり領域は全て正の座標のみを
      // 使うため、この`Clip.none`による見た目上のはみ出しは発生しない
      // （並び替えハンドルは`table_col.dart`/`table_handle_gutter.dart`側で
      // 実領域のガターとして確保済み、2026-09-27修正）。
      clipBehavior: Clip.none,
      children: [
        table,
        ..._buildResizeStrips(context),
        _buildColDropIndicator(context),
        _buildRowDropIndicator(context),
        _buildColDragHighlight(context),
        _buildRowDragHighlight(context),
      ],
    );
  }

  // ドラッグ中の列/行全体を紫の角丸枠で囲むハイライト（2026-09-28追加、
  // ユーザー指示）。ドラッグ開始位置からの累積オフセット分だけ位置をずらし、
  // ポインターに追従しているように見せる。
  Widget _buildColDragHighlight(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _colDragIndex,
      builder: (context, index, _) {
        if (index == null) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<double>(
          valueListenable: _colDragOffset,
          builder: (context, offset, _) {
            final tableNode = widget.tableNode;
            final left =
                kTableHandleGutterSize + tableNode.colBoundaryX(index) + offset;
            return Positioned(
              left: left,
              top: kTableHandleGutterSize,
              width: tableNode.getColWidth(index),
              height: tableNode.colsHeight,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.editorState.editorStyle.cursorColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRowDragHighlight(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _rowDragIndex,
      builder: (context, index, _) {
        if (index == null) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<double>(
          valueListenable: _rowDragOffset,
          builder: (context, offset, _) {
            final tableNode = widget.tableNode;
            final top =
                kTableHandleGutterSize + tableNode.rowTopY(index) + offset;
            return Positioned(
              left: 0,
              top: top,
              width: kTableHandleGutterSize + tableNode.tableWidth,
              height: tableNode.getRowHeight(index),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.editorState.editorStyle.cursorColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 列/行の並び替えドラッグ中、ドロップ先の境界を示す線
  // （2026-09-28追加、ユーザー指示）。`IgnorePointer`でホバー/クリックを
  // 奪わないようにする。色は範囲選択の枠線オーバーレイと同じ
  // `cursorColor`で統一する。
  Widget _buildColDropIndicator(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _colDropIndex,
      builder: (context, dropIndex, _) {
        if (dropIndex == null) {
          return const SizedBox.shrink();
        }
        final x =
            kTableHandleGutterSize + widget.tableNode.colBoundaryX(dropIndex);
        return Positioned(
          left: x - 1,
          top: kTableHandleGutterSize,
          width: 2,
          height: widget.tableNode.colsHeight,
          child: IgnorePointer(
            child: Container(color: widget.editorState.editorStyle.cursorColor),
          ),
        );
      },
    );
  }

  Widget _buildRowDropIndicator(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _rowDropIndex,
      builder: (context, dropIndex, _) {
        if (dropIndex == null) {
          return const SizedBox.shrink();
        }
        final y = kTableHandleGutterSize + widget.tableNode.rowTopY(dropIndex);
        return Positioned(
          left: 0,
          top: y - 1,
          width: kTableHandleGutterSize + widget.tableNode.tableWidth,
          height: 2,
          child: IgnorePointer(
            child: Container(color: widget.editorState.editorStyle.cursorColor),
          ),
        );
      },
    );
  }

  // 列の並び替えドラッグ（2026-09-28追加、ユーザー指示）。
  void _onColHandleDragStart(int colIdx, DragStartDetails details) {
    _colDragFrom = colIdx;
    _colDragIndex.value = colIdx;
    _colDragOffset.value = 0;
    _updateColDropIndicator(details.globalPosition);
  }

  void _onColHandleDragUpdate(int colIdx, DragUpdateDetails details) {
    _colDragOffset.value += details.delta.dx;
    _updateColDropIndicator(details.globalPosition);
  }

  void _updateColDropIndicator(Offset globalPosition) {
    final box = _tableContentKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    final x = box.globalToLocal(globalPosition).dx - kTableHandleGutterSize;
    final tableNode = widget.tableNode;
    final c = tableNode.colIndexAtX(x).clamp(0, tableNode.colsLen - 1);
    final mid = (tableNode.colBoundaryX(c) + tableNode.colBoundaryX(c + 1)) / 2;
    _colDropIndex.value = x < mid ? c : c + 1;
  }

  void _onColHandleDragEnd(int colIdx, DragEndDetails details) {
    final from = _colDragFrom;
    final to = _colDropIndex.value;
    _colDragFrom = null;
    _colDropIndex.value = null;
    _colDragIndex.value = null;
    _colDragOffset.value = 0;
    if (from == null || to == null) {
      return;
    }
    final transaction = widget.editorState.transaction;
    widget.tableNode.moveCol(from, to, transaction: transaction);
    if (transaction.operations.isNotEmpty) {
      transaction.afterSelection = transaction.beforeSelection;
      widget.editorState.apply(transaction);
    }
  }

  // ドラッグが途中でキャンセルされた場合（例: ポインターが画面外に出る等）に
  // ドロップ位置インジケーターが残り続けないようにする（2026-09-28追加）。
  void _onColHandleDragCancel(int colIdx) {
    _colDragFrom = null;
    _colDropIndex.value = null;
    _colDragIndex.value = null;
    _colDragOffset.value = 0;
  }

  // 行の並び替えドラッグ。列側の縦横を入れ替えた対称実装。
  void _onRowHandleDragStart(int rowIdx, DragStartDetails details) {
    _rowDragFrom = rowIdx;
    _rowDragIndex.value = rowIdx;
    _rowDragOffset.value = 0;
    _updateRowDropIndicator(details.globalPosition);
  }

  void _onRowHandleDragUpdate(int rowIdx, DragUpdateDetails details) {
    _rowDragOffset.value += details.delta.dy;
    _updateRowDropIndicator(details.globalPosition);
  }

  void _updateRowDropIndicator(Offset globalPosition) {
    final box = _tableContentKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    final y = box.globalToLocal(globalPosition).dy - kTableHandleGutterSize;
    final tableNode = widget.tableNode;
    final r = tableNode.rowIndexAtY(y).clamp(0, tableNode.rowsLen - 1);
    final mid = (tableNode.rowTopY(r) + tableNode.rowTopY(r + 1)) / 2;
    _rowDropIndex.value = y < mid ? r : r + 1;
  }

  void _onRowHandleDragEnd(int rowIdx, DragEndDetails details) {
    final from = _rowDragFrom;
    final to = _rowDropIndex.value;
    _rowDragFrom = null;
    _rowDropIndex.value = null;
    _rowDragIndex.value = null;
    _rowDragOffset.value = 0;
    if (from == null || to == null) {
      return;
    }
    final transaction = widget.editorState.transaction;
    widget.tableNode.moveRow(from, to, transaction: transaction);
    if (transaction.operations.isNotEmpty) {
      transaction.afterSelection = transaction.beforeSelection;
      widget.editorState.apply(transaction);
    }
  }

  void _onRowHandleDragCancel(int rowIdx) {
    _rowDragFrom = null;
    _rowDropIndex.value = null;
    _rowDragIndex.value = null;
    _rowDragOffset.value = 0;
  }

  // 各列の右側罫線（列幅リサイズ用）ごとの当たり領域。見た目上の罫線の
  // 太さ（`config.borderWidth`）はそのままに、判定領域だけ広げる
  // （2026-09-27、ユーザー指摘: 「広げられる範囲が狭すぎる」への対応）。
  // 座標は`TableRowHandleGutter`の幅（`kTableHandleGutterSize`）ぶん
  // 右にずれるため、その分をオフセットする。
  List<Widget> _buildResizeStrips(BuildContext context) {
    const hitWidth = 12.0;
    return List.generate(widget.tableNode.colsLen, (i) {
      final centerX =
          kTableHandleGutterSize + widget.tableNode.colDividerCenterX(i);
      return Positioned(
        left: centerX - hitWidth / 2,
        top: kTableHandleGutterSize,
        width: hitWidth,
        height: widget.tableNode.colsHeight,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => _resizeHoverCol.value = i,
          onExit: (_) => _resizeHoverCol.value = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _resizeDraggingCol.value = i;
              _wasAtEndWhenResizeStarted = _isScrolledToEnd();
            },
            onHorizontalDragUpdate: (details) {
              final colWidth = widget.tableNode.getColWidth(i);
              widget.tableNode.setColWidth(i, colWidth + details.delta.dx);
              if (_wasAtEndWhenResizeStarted) {
                _scrollToEndAfterLayout(animate: false);
              }
            },
            onHorizontalDragEnd: (_) {
              final transaction = widget.editorState.transaction;
              widget.tableNode.setColWidth(
                i,
                widget.tableNode.getColWidth(i),
                transaction: transaction,
                force: true,
              );
              transaction.afterSelection = transaction.beforeSelection;
              widget.editorState.apply(transaction);
              _resizeDraggingCol.value = null;
              if (_wasAtEndWhenResizeStarted) {
                _scrollToEndAfterLayout();
              }
            },
          ),
        ),
      );
    });
  }

  bool _isScrolledToEnd() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) {
      return false;
    }
    return controller.offset >= controller.position.maxScrollExtent - 1;
  }

  // 列の追加・列幅リサイズによって表が広がった直後、表示領域の右端に隠れて
  // 見えなくならないよう追従スクロールする（2026-09-27追加、ユーザー指摘）。
  // レイアウト確定後でないと`maxScrollExtent`が新しい幅を反映しないため、
  // 1フレーム待ってから実行する。
  void _scrollToEndAfterLayout({bool animate = true}) {
    final controller = widget.scrollController;
    if (controller == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) {
        return;
      }
      final maxExtent = controller.position.maxScrollExtent;
      if (animate) {
        controller.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        controller.jumpTo(maxExtent);
      }
    });
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => TableCol(
        colIdx: i,
        editorState: widget.editorState,
        tableNode: widget.tableNode,
        menuBuilder: widget.menuBuilder,
        tableStyle: widget.tableStyle,
        resizeHoverColNotifier: _resizeHoverCol,
        resizeDraggingColNotifier: _resizeDraggingCol,
        onDragStart: (details) => _onColHandleDragStart(i, details),
        onDragUpdate: (details) => _onColHandleDragUpdate(i, details),
        onDragEnd: (details) => _onColHandleDragEnd(i, details),
        onDragCancel: () => _onColHandleDragCancel(i),
        colDragIndexNotifier: _colDragIndex,
        colDragOffsetNotifier: _colDragOffset,
        rowDragIndexNotifier: _rowDragIndex,
        rowDragOffsetNotifier: _rowDragOffset,
      ),
    );
  }
}
