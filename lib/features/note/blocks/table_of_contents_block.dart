import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:provider/provider.dart' hide Consumer;

import '../../../l10n/strings.dart';
import '../../../utils/note_title.dart';

/// 文書内の見出し一覧をタップでジャンプできる形で表示する目次ブロック
/// （2026-09-27追加、ユーザー指示）。見出しの追加・削除に追従するため、
/// `editorState.transactionStream`を監視して都度作り直す（このセッションで
/// 既に使っている`_openFormatBottomSheet`の`StreamBuilder`パターンを踏襲）。
class TableOfContentsBlockKeys {
  const TableOfContentsBlockKeys._();

  static const String type = 'table_of_contents';
}

Node tableOfContentsNode() {
  return Node(type: TableOfContentsBlockKeys.type);
}

List<Node> _collectHeadings(Node root) {
  final result = <Node>[];
  void walk(Node node) {
    if (node.type == HeadingBlockKeys.type) result.add(node);
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final child in root.children) {
    walk(child);
  }
  return result;
}

class TableOfContentsBlockComponentBuilder extends BlockComponentBuilder {
  TableOfContentsBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return TableOfContentsBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => true;
}

class TableOfContentsBlockComponentWidget extends BlockComponentStatefulWidget {
  const TableOfContentsBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<TableOfContentsBlockComponentWidget> createState() =>
      _TableOfContentsBlockComponentWidgetState();
}

// SelectableMixinの実装は`divider_block_component.dart`に倣った（非テキストの
// 「不可分ブロック」向けの標準的な実装）。
class _TableOfContentsBlockComponentWidgetState
    extends State<TableOfContentsBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _contentKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  void _jumpTo(Node headingNode) {
    editorState.selection = Selection.collapsed(
      Position(path: headingNode.path, offset: 0),
    );
    editorState.service.scrollService?.jumpTo(headingNode.path.first);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = StreamBuilder<EditorTransactionValue>(
      stream: editorState.transactionStream,
      builder: (context, _) {
        final headings = _collectHeadings(editorState.document.root);
        if (headings.isEmpty) {
          return Consumer(
            builder: (context, ref, _) => Text(
              ref.watch(appStringsProvider).noteTableOfContentsEmpty,
              style: DefaultTextStyle.of(context).style.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final heading in headings)
              Padding(
                padding: EdgeInsets.only(
                  left:
                      ((heading.attributes[HeadingBlockKeys.level] as int? ??
                              1) -
                          1) *
                      16.0,
                  top: 2,
                  bottom: 2,
                ),
                child: InkWell(
                  onTap: () => _jumpTo(heading),
                  child: Text(
                    plainTextWithoutMarkdownPrefix(heading).trim().isEmpty
                        ? ' '
                        : plainTextWithoutMarkdownPrefix(heading).trim(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    child = Padding(key: _contentKey, padding: padding, child: child);

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
        BlockSelectionType.cursor,
        BlockSelectionType.selection,
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

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    return getRectsInSelection(
      Selection.collapsed(position),
      shiftWithBaseOffset: shiftWithBaseOffset,
    ).firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final contentBox = _contentKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && contentBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? contentBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            contentBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);

  @override
  TextDirection textDirection() => TextDirection.ltr;
}
