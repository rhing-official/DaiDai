import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:provider/provider.dart' hide Consumer;

import '../../../l10n/strings.dart';
import '../../../utils/note_title.dart';
import '../block_move_drag.dart';

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

/// 見出しレベルの列を、最小レベルを第0階層とする相対階層（最大3）へ変換する
/// （例: [2,3,3,2] → [0,1,1,0]、[1,2,3,4,5] → [0,1,2,3,3]）。見出しの
/// 使い方（H1から使う/H2から使う等）に依らず、目次の字下げが揃うようにする。
List<int> tocIndentLevels(List<int> levels) {
  if (levels.isEmpty) return const [];
  final minLevel = levels.reduce((a, b) => a < b ? a : b);
  return [for (final level in levels) (level - minLevel).clamp(0, 3)];
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

  /// 目次の項目の開閉（保存しない、このブロック表示中のみ）。
  bool _expanded = true;

  final _headerKey = GlobalKey();
  final List<GlobalKey> _itemKeys = [];

  bool _contains(GlobalKey key, Offset globalPosition) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final local = box.globalToLocal(globalPosition);
    return (Offset.zero & box.size).contains(local);
  }

  void _onTap(Offset globalPosition, List<Node> headings) {
    if (_contains(_headerKey, globalPosition)) {
      setState(() => _expanded = !_expanded);
      return;
    }
    if (!_expanded) return;
    for (var i = 0; i < headings.length && i < _itemKeys.length; i++) {
      if (_contains(_itemKeys[i], globalPosition)) {
        _jumpTo(headings[i]);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = editorState.editorStyle.textStyleConfiguration.text;
    final textColor =
        baseStyle.color ?? Theme.of(context).colorScheme.onSurface;
    final dividerColor = textColor.withValues(alpha: 0.14);

    Widget child = StreamBuilder<EditorTransactionValue>(
      stream: editorState.transactionStream,
      builder: (context, _) {
        final headings = _collectHeadings(editorState.document.root);
        final indents = tocIndentLevels([
          for (final h in headings)
            h.attributes[HeadingBlockKeys.level] as int? ?? 1,
        ]);
        return Consumer(
          builder: (context, ref, _) {
            final strings = ref.watch(appStringsProvider);
            _itemKeys
              ..clear()
              ..addAll([for (final _ in headings) GlobalKey()]);
            // 目次全体をドラッグの掴み所にする（2026-10-04追加、ユーザー指示）。
            // ドラッグ認識は押下で勝つため、`InkWell`ではなく
            // `BlockMoveHandle.onTap`で開閉・ジャンプを受ける。
            return BlockMoveHandle(
              node: node,
              editorState: editorState,
              color: textColor.withValues(alpha: 0.55),
              onTap: (position) => _onTap(position, headings),
              child: Container(
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.06),
                  border: Border.all(color: dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      key: _headerKey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _expanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: 20,
                            color: textColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            strings.noteMenuTableOfContents,
                            style: baseStyle.copyWith(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_expanded && headings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                        child: Text(
                          strings.noteTableOfContentsEmpty,
                          style: baseStyle.copyWith(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    if (_expanded)
                      for (var i = 0; i < headings.length; i++)
                        _buildItem(
                          _itemKeys[i],
                          headings[i],
                          indents[i],
                          baseStyle,
                          textColor,
                          dividerColor,
                          isLast: i == headings.length - 1,
                        ),
                  ],
                ),
              ),
            );
          },
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
      // 目次はハイライト選択させない（2026-10-04、ユーザー指示）。
      supportTypes: const [],
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

  Widget _buildItem(
    GlobalKey key,
    Node heading,
    int depth,
    TextStyle baseStyle,
    Color textColor,
    Color dividerColor, {
    required bool isLast,
  }) {
    final label = plainTextWithoutMarkdownPrefix(heading).trim();
    // 階層が深いほど字下げし、やや小さく淡くする（最上位=本文の文字色）。
    final indent = 12.0 + depth * 16.0;
    return KeyedSubtree(
      key: key,
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(bottom: BorderSide(color: dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 9, 12, 9),
            child: Text(
              label.isEmpty ? ' ' : label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: baseStyle.copyWith(
                color: textColor.withValues(alpha: depth == 0 ? 1 : 0.78),
                fontSize: depth == 0 ? 15 : 14,
              ),
            ),
          ),
        ),
      ),
    );
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
