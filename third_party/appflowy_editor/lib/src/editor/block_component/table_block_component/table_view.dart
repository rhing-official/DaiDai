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
    this.scrollController,
  });

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

  @override
  void dispose() {
    _resizeHoverCol.dispose();
    _resizeDraggingCol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = Row(
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
      ],
    );
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
      ),
    );
  }
}
