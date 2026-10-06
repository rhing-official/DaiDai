import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/selection/block_selection_area.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_view.dart';

class TableBlockKeys {
  const TableBlockKeys._();

  static const String type = 'table';

  static const String colDefaultWidth = 'colDefaultWidth';

  static const String rowDefaultHeight = 'rowDefaultHeight';

  static const String colMinimumWidth = 'colMinimumWidth';

  static const String borderWidth = 'borderWidth';

  static const String colsLen = 'colsLen';

  static const String rowsLen = 'rowsLen';

  static const String colsHeight = 'colsHeight';
}

class TableStyle {
  final double colWidth;
  final double rowHeight;
  final double colMinimumWidth;
  final double borderWidth;
  final Widget addIcon;
  final Widget handlerIcon;
  final Color borderColor;
  final Color borderHoverColor;

  const TableStyle({
    this.colWidth = 160,
    this.rowHeight = 40,
    this.colMinimumWidth = 40,
    this.borderWidth = 2,
    this.addIcon = TableDefaults.addIcon,
    this.handlerIcon = TableDefaults.handlerIcon,
    this.borderColor = TableDefaults.borderColor,
    this.borderHoverColor = TableDefaults.borderHoverColor,
  });
}

class TableDefaults {
  const TableDefaults._();

  static double colWidth = 160.0;

  static double rowHeight = 40.0;

  static double colMinimumWidth = 40.0;

  static double borderWidth = 2.0;

  static const Widget addIcon = Icon(Icons.add, size: 20);

  static const Widget handlerIcon = Icon(Icons.drag_indicator);

  static const Color borderColor = Colors.grey;

  static const Color borderHoverColor = Colors.blue;
}

enum TableDirection { row, col }

typedef TableBlockComponentMenuBuilder = Widget Function(
  Node,
  EditorState,
  int,
  TableDirection,
  VoidCallback?,
  VoidCallback?,
);

class TableBlockComponentBuilder extends BlockComponentBuilder {
  TableBlockComponentBuilder({
    super.configuration,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    this.cornerHandleBuilder,
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  // 表の左上の角（列ハンドル用ガターと行ハンドル用ガターが交わる空き）に
  // 置くウィジェットを差し込むためのコールバック（2026-10-04追加、DaiDai
  // patch。表全体をドラッグで移動するハンドル用）。nullなら従来どおり空白。
  final Widget Function(BuildContext context, Node node)? cornerHandleBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    TableDefaults.colWidth = tableStyle.colWidth;
    TableDefaults.rowHeight = tableStyle.rowHeight;
    TableDefaults.colMinimumWidth = tableStyle.colMinimumWidth;
    TableDefaults.borderWidth = tableStyle.borderWidth;
    return TableBlockComponentWidget(
      key: node.key,
      tableNode: TableNode(node: node),
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      cornerHandleBuilder: cornerHandleBuilder,
      tableStyle: tableStyle,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) {
        // check the node is valid
        if (node.attributes.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: node is empty');
          return false;
        }

        // check the node has rowPosition and colPosition
        if (!node.attributes.containsKey(TableBlockKeys.colsLen) ||
            !node.attributes.containsKey(TableBlockKeys.rowsLen)) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: node has no colsLen or rowsLen',
          );
          return false;
        }

        final colsLen = node.attributes[TableBlockKeys.colsLen];
        final rowsLen = node.attributes[TableBlockKeys.rowsLen];

        // check its children
        final children = node.children;
        if (children.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: children is empty');
          return false;
        }

        if (children.length != colsLen * rowsLen) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: children length(${children.length}) is not equal to colsLen * rowsLen($colsLen * $rowsLen)',
          );
          return false;
        }

        // all children should contain rowPosition and colPosition
        for (var i = 0; i < colsLen; i++) {
          for (var j = 0; j < rowsLen; j++) {
            final child = children.where(
              (n) =>
                  n.attributes[TableCellBlockKeys.colPosition] == i &&
                  n.attributes[TableCellBlockKeys.rowPosition] == j,
            );
            if (child.isEmpty) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is empty',
              );
              return false;
            }

            // should only contains one child
            if (child.length != 1) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is not unique',
              );
              return false;
            }
          }
        }

        return true;
      };
}

class TableBlockComponentWidget extends BlockComponentStatefulWidget {
  const TableBlockComponentWidget({
    super.key,
    required this.tableNode,
    required super.node,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    this.cornerHandleBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;
  final Widget Function(BuildContext context, Node node)? cornerHandleBuilder;

  @override
  State<TableBlockComponentWidget> createState() =>
      _TableBlockComponentWidgetState();
}

class _TableBlockComponentWidgetState extends State<TableBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);
  final _scrollController = ScrollController();

  // 複数セルにまたがる選択が行われた時、選択範囲全体を囲む枠線を描画する
  // ための矩形（2026-09-27追加、ユーザー指示。Notion/スプレッドシートの
  // セル範囲選択を参考にした）。単一セル内のテキスト選択の間はnullのままで、
  // 従来通りの通常のテキストハイライトに任せる。
  Rect? _rangeSelectionRect;

  @override
  void initState() {
    super.initState();
    editorState.selectionNotifier.addListener(_updateRangeSelectionRect);
    _scrollController.addListener(_updateRangeSelectionRect);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateRangeSelectionRect(),
    );
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_updateRangeSelectionRect);
    _scrollController.removeListener(_updateRangeSelectionRect);
    super.dispose();
  }

  void _updateRangeSelectionRect() {
    if (!mounted) return;
    final selection = editorState.selection;
    final rect = (selection != null && !selection.isCollapsed)
        ? _computeCellRangeRect(selection)
        : null;
    if (rect != _rangeSelectionRect) {
      setState(() => _rangeSelectionRect = rect);
    }
  }

  Node? _findAncestorCell(Path path) {
    var node = editorState.getNodeAtPath(path);
    while (node != null && node.type != TableCellBlockKeys.type) {
      node = node.parent;
    }
    return node;
  }

  Rect? _computeCellRangeRect(Selection selection) {
    final startCell = _findAncestorCell(selection.start.path);
    final endCell = _findAncestorCell(selection.end.path);
    if (startCell == null ||
        endCell == null ||
        startCell.parent != widget.node ||
        endCell.parent != widget.node ||
        startCell == endCell) {
      return null;
    }
    final startRow =
        startCell.attributes[TableCellBlockKeys.rowPosition] as int;
    final startCol =
        startCell.attributes[TableCellBlockKeys.colPosition] as int;
    final endRow = endCell.attributes[TableCellBlockKeys.rowPosition] as int;
    final endCol = endCell.attributes[TableCellBlockKeys.colPosition] as int;
    final rowMin = min(startRow, endRow);
    final rowMax = max(startRow, endRow);
    final colMin = min(startCol, endCol);
    final colMax = max(startCol, endCol);
    final topLeftCell = widget.tableNode.getCell(colMin, rowMin);
    final bottomRightCell = widget.tableNode.getCell(colMax, rowMax);
    final tableBox = tableKey.currentContext?.findRenderObject();
    final topLeftBox = topLeftCell.key.currentContext?.findRenderObject();
    final bottomRightBox =
        bottomRightCell.key.currentContext?.findRenderObject();
    if (tableBox is! RenderBox ||
        topLeftBox is! RenderBox ||
        bottomRightBox is! RenderBox) {
      return null;
    }
    final topLeft = topLeftBox.localToGlobal(Offset.zero, ancestor: tableBox);
    final bottomRight = bottomRightBox.localToGlobal(
      bottomRightBox.size.bottomRight(Offset.zero),
      ancestor: tableBox,
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollbar(
      controller: _scrollController,
      // 列の追加・列幅リサイズで表が表示領域の右端を超えて見えなくなっても
      // スクロール可能なことが常に分かるよう、常時表示にする
      // （2026-09-27追加、ユーザー指摘）。
      thumbVisibility: true,
      child: SingleChildScrollView(
        // 左のパディングは本文（段落等）の左端と揃えるために無くした
        // （2026-09-27修正、ユーザー指示）。以前は列のリサイズハンドル用に
        // 10px確保していたが、ホバー時のみ表示されるハンドルのはみ出しより
        // 本文との左揃えを優先する。表は行の並び替えハンドル用ガターの分
        // だけ右にずれる（2026-09-27、ユーザー確認済み）。
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: TableView(
          tableNode: widget.tableNode,
          editorState: editorState,
          menuBuilder: widget.menuBuilder,
          cornerHandleBuilder: widget.cornerHandleBuilder,
          tableStyle: widget.tableStyle,
          scrollController: _scrollController,
        ),
      ),
    );

    // 表領域上の横ドラッグを祖先（ノート画面の右スワイプで戻る検出）へ
    // 伝えない。表がスクロール不要な幅でも、表の上の横操作で画面が
    // 戻らないようにする（2026-10-06追加、ユーザー指示）。
    child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: (_) {},
      onHorizontalDragEnd: (_) {},
      child: child,
    );

    // 複数セル選択中は、各セルの個別ハイライトの代わりに選択範囲全体を囲む
    // 枠線オーバーレイ（下記）だけを見せる（2026-09-27追加、ユーザー指示）。
    if (_rangeSelectionRect != null) {
      child = SuppressBlockSelectionHighlight(child: child);
    }

    child = Padding(
      key: tableKey,
      padding: padding,
      child: child,
    );

    final rangeSelectionRect = _rangeSelectionRect;
    if (rangeSelectionRect != null) {
      child = Stack(
        children: [
          child,
          Positioned.fromRect(
            rect: rangeSelectionRect,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: editorState.editorStyle.cursorColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  color: editorState.editorStyle.selectionColor,
                ),
              ),
            ),
          ),
        ],
      );
    }

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  final tableKey = GlobalKey();

  RenderBox get _renderBox => context.findRenderObject() as RenderBox;

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = context.findRenderObject();
    final tableBox = tableKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && tableBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? tableBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            tableBox.size,
      ];
    }
    return [Offset.zero & _renderBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox.localToGlobal(offset);

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final size = _renderBox.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }
}

SelectionMenuItem tableMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.table,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.table_view,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['table'],
  handler: (editorState, _, __) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final currentNode = editorState.getNodeAtPath(selection.end.path);
    if (currentNode == null) {
      return;
    }

    final tableNode = TableNode.fromList([
      ['', ''],
      ['', ''],
    ]);

    final transaction = editorState.transaction;
    final delta = currentNode.delta;
    if (delta != null && delta.isEmpty) {
      transaction
        ..insertNode(selection.end.path, tableNode.node)
        ..deleteNode(currentNode);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path + [0, 0],
          offset: 0,
        ),
      );
    } else {
      transaction.insertNode(selection.end.path.next, tableNode.node);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path.next + [0, 0],
          offset: 0,
        ),
      );
    }

    editorState.apply(transaction);
  },
);
