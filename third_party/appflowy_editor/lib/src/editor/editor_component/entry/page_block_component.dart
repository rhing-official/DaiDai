import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/widget/ignore_parent_gesture.dart';
import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_handle_gutter.dart'
    show kTableHandleGutterSize;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PageBlockKeys {
  static const String type = 'page';
}

Node pageNode({
  required Iterable<Node> children,
  Attributes attributes = const {},
}) {
  return Node(
    type: PageBlockKeys.type,
    children: children,
    attributes: attributes,
  );
}

class PageBlockComponentBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    return PageBlockComponent(
      key: blockComponentContext.node.key,
      node: blockComponentContext.node,
      header: blockComponentContext.header,
      footer: blockComponentContext.footer,
      wrapper: blockComponentContext.wrapper,
    );
  }
}

/// 表は、左の行ハンドル（ガター）の分だけ左へ出し、表の左端を本文の左端に揃える
/// （DaiDai patch 2026-11-15。以前はガターの分だけ表が右にずれていた）。ガターは左の余白に
/// 入る。余白が足りない時（モバイル）は、足りない分だけ右にずれる。
EdgeInsets _blockPadding(EdgeInsets padding, Node node) {
  if (node.type != TableBlockKeys.type) return padding;
  return padding.copyWith(
      left: math.max(0, padding.left - kTableHandleGutterSize));
}

class PageBlockComponent extends BlockComponentStatelessWidget {
  const PageBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.header,
    this.footer,
    this.wrapper,
  });

  final Widget? header;
  final Widget? footer;
  final BlockComponentWrapper? wrapper;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final scrollController = context.read<EditorScrollController?>();
    final items = node.children;

    if (scrollController == null || scrollController.shrinkWrap) {
      return SingleChildScrollView(
        child: Builder(
          builder: (context) {
            final scroller = Scrollable.maybeOf(context);
            if (scroller != null) {
              editorState.updateAutoScroller(scroller);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (header != null) header!,
                ...items.map(
                  (e) {
                    Widget child = editorState.renderer.build(context, e);
                    if (wrapper != null) {
                      child = wrapper!(context, node: e, child: child);
                    }
                    return Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            editorState.editorStyle.maxWidth ?? double.infinity,
                      ),
                      padding:
                          _blockPadding(editorState.editorStyle.padding, e),
                      child: child,
                    );
                  },
                ),
                if (footer != null) footer!,
              ],
            );
          },
        ),
      );
    } else {
      int extentCount = 0;
      if (header != null) extentCount++;
      if (footer != null) extentCount++;

      return ScrollablePositionedList.builder(
        shrinkWrap: scrollController.shrinkWrap,
        scrollDirection: Axis.vertical,
        itemCount: items.length + extentCount,
        itemBuilder: (context, index) {
          editorState.updateAutoScroller(Scrollable.of(context));
          if (header != null && index == 0) {
            return IgnoreEditorSelectionGesture(
              child: header!,
            );
          }

          if (footer != null && index == (items.length - 1) + extentCount) {
            return IgnoreEditorSelectionGesture(
              child: footer!,
            );
          }

          final node = items[index - (header != null ? 1 : 0)];
          Widget child = editorState.renderer.build(
            context,
            node,
          );
          if (wrapper != null) {
            child = wrapper!(context, node: node, child: child);
          }

          // 各ブロックは左端に寄せる（DaiDai patch 2026-11-15。以前はCenterで、幅が本文より
          // 狭いブロック（表・画像・リンクのプレビューなど）が中央に寄っていた）。
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: editorState.editorStyle.maxWidth ?? double.infinity,
              ),
              padding: _blockPadding(editorState.editorStyle.padding, node),
              child: child,
            ),
          );
        },
        itemScrollController: scrollController.itemScrollController,
        scrollOffsetController: scrollController.scrollOffsetController,
        itemPositionsListener: scrollController.itemPositionsListener,
        scrollOffsetListener: scrollController.scrollOffsetListener,
      );
    }
  }
}
