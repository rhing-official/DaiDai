import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/markdown_prefix_reveal.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HeadingBlockKeys {
  const HeadingBlockKeys._();

  static const String type = 'heading';

  /// The level data of a heading block.
  ///
  /// The value is a int.
  static const String level = 'level';

  static const String delta = blockComponentDelta;

  static const String backgroundColor = blockComponentBackgroundColor;

  static const String textDirection = blockComponentTextDirection;

  /// Markdown変換で残した先頭記号（`# `等）の文字数（2026-09-26追加、
  /// DaiDai側の対応）。`markdown_prefix_reveal.dart`参照。
  static const String markdownPrefixLength = 'markdownPrefixLength';
}

Node headingNode({
  required int level,
  String? text,
  Delta? delta,
  String? textDirection,
  Attributes? attributes,
}) {
  assert(level >= 1 && level <= 6);
  return Node(
    type: HeadingBlockKeys.type,
    attributes: {
      HeadingBlockKeys.delta: (delta ?? (Delta()..insert(text ?? ''))).toJson(),
      HeadingBlockKeys.level: level.clamp(1, 6),
      if (attributes != null) ...attributes,
      if (textDirection != null) HeadingBlockKeys.textDirection: textDirection,
    },
  );
}

class HeadingBlockComponentBuilder extends BlockComponentBuilder {
  HeadingBlockComponentBuilder({
    super.configuration,
    this.textStyleBuilder,
  });

  /// The text style of the heading block.
  final TextStyle Function(int level)? textStyleBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return HeadingBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      textStyleBuilder: textStyleBuilder,
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
}

class HeadingBlockComponentWidget extends BlockComponentStatefulWidget {
  const HeadingBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.textStyleBuilder,
  });

  /// The text style of the heading block.
  final TextStyle Function(int level)? textStyleBuilder;

  @override
  State<HeadingBlockComponentWidget> createState() =>
      _HeadingBlockComponentWidgetState();
}

class _HeadingBlockComponentWidgetState
    extends State<HeadingBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: HeadingBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  late final editorState = Provider.of<EditorState>(context, listen: false);

  int get level => widget.node.attributes[HeadingBlockKeys.level] as int? ?? 1;

  // カーソル/選択がこのノードの行にあるかどうか（2026-09-26追加、DaiDai側の
  // 対応）。`markdown_prefix_reveal.dart`参照。
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = _computeIsFocused();
    editorState.selectionNotifier.addListener(_handleSelectionChanged);
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_handleSelectionChanged);
    super.dispose();
  }

  void _handleSelectionChanged() {
    final next = _computeIsFocused();
    if (next != _isFocused && mounted) {
      setState(() => _isFocused = next);
    }
  }

  bool _computeIsFocused() {
    final selection = editorState.selection;
    if (selection == null) return false;
    final normalized = selection.normalized;
    return !(node.path < normalized.start.path ||
        node.path > normalized.end.path);
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      // Related issue: https://github.com/AppFlowy-IO/AppFlowy/issues/3175
      // make the width of the rich text as small as possible to avoid
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        textDirection: textDirection,
        children: [
          Flexible(
            child: AppFlowyRichText(
              key: forwardKey,
              delegate: this,
              node: widget.node,
              editorState: editorState,
              textAlign: alignment?.toTextAlign ?? textAlign,
              textSpanDecorator: (textSpan) {
                var result = textSpan.updateTextStyle(
                  textStyleWithTextSpan(textSpan: textSpan),
                );
                result = result.updateTextStyle(
                  widget.textStyleBuilder?.call(level) ??
                      defaultTextStyle(level),
                );
                // 2026-09-26追加、DaiDai側の対応。
                result = hideMarkdownPrefixWhenNotFocused(
                  textSpan: result,
                  prefixLength: widget.node
                          .attributes[HeadingBlockKeys.markdownPrefixLength]
                      as int?,
                  isFocused: _isFocused,
                );
                return result;
              },
              placeholderText: placeholderText,
              placeholderTextSpanDecorator: (textSpan) => textSpan
                  .updateTextStyle(
                    widget.textStyleBuilder?.call(level) ??
                        defaultTextStyle(level),
                  )
                  .updateTextStyle(
                    placeholderTextStyleWithTextSpan(textSpan: textSpan),
                  ),
              textDirection: textDirection,
              cursorColor: editorState.editorStyle.cursorColor,
              selectionColor: editorState.editorStyle.selectionColor,
              cursorWidth: editorState.editorStyle.cursorWidth,
            ),
          ),
        ],
      ),
    );

    child = BlockSelectionContainer(
      node: node,
      key: blockComponentKey,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    child = Container(
      padding: padding,
      decoration: decoration,
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

  TextStyle? defaultTextStyle(int level) {
    final fontSizes = [32.0, 28.0, 24.0, 18.0, 18.0, 18.0];
    final fontSize = fontSizes.elementAtOrNull(level) ?? 18.0;
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );
  }
}
