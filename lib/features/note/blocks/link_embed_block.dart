import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../../models/app_ui_style.dart';
import '../../../providers/app_ui_style_provider.dart';
import '../../../widgets/link_preview_card.dart';

/// URLを埋め込むカスタムブロック（2026-09-27追加、ユーザー指示）。
/// 編集機能は持たせず、チャットのリンクプレビューと同じ
/// `LinkPreviewCard`をそのまま表示する読み取り専用ブロック。
class LinkEmbedBlockKeys {
  const LinkEmbedBlockKeys._();

  static const String type = 'link_embed';
  static const String url = 'url';
}

Node linkEmbedNode({required String url}) {
  return Node(
    type: LinkEmbedBlockKeys.type,
    attributes: {LinkEmbedBlockKeys.url: url},
  );
}

class LinkEmbedBlockComponentBuilder extends BlockComponentBuilder {
  LinkEmbedBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return LinkEmbedBlockComponentWidget(
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
      (node) => node.attributes[LinkEmbedBlockKeys.url] is String;
}

class LinkEmbedBlockComponentWidget extends BlockComponentStatefulWidget {
  const LinkEmbedBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<LinkEmbedBlockComponentWidget> createState() =>
      _LinkEmbedBlockComponentWidgetState();
}

// SelectableMixinの実装は`divider_block_component.dart`の
// `_DividerBlockComponentWidgetState`に倣った（カーソルはブロック全体を
// 1つの位置として覆う、非テキストの「不可分ブロック」向けの標準的な実装）。
class _LinkEmbedBlockComponentWidgetState
    extends State<LinkEmbedBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _contentKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final url = widget.node.attributes[LinkEmbedBlockKeys.url] as String? ?? '';

    Widget child = Consumer(
      builder: (context, ref, _) {
        final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
        return LinkPreviewCard(url: url, isGekiga: isGekiga, isMe: false);
      },
    );

    child = Padding(key: _contentKey, padding: padding, child: child);

    final editorState = context.read<EditorState>();
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
