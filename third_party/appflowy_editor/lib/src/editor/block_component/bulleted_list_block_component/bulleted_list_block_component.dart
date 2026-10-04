import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/block_icon_builder.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/markdown_prefix_reveal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BulletedListBlockKeys {
  const BulletedListBlockKeys._();

  static const String type = 'bulleted_list';

  static const String delta = blockComponentDelta;

  static const String backgroundColor = blockComponentBackgroundColor;

  static const String textDirection = blockComponentTextDirection;

  /// Markdown変換で残した先頭記号（`- `/`* `）の文字数（2026-09-26追加、
  /// DaiDai側の対応）。`markdown_prefix_reveal.dart`参照。
  static const String markdownPrefixLength = 'markdownPrefixLength';
}

Node bulletedListNode({
  String? text,
  Delta? delta,
  String? textDirection,
  Attributes? attributes,
  Iterable<Node>? children,
}) {
  return Node(
    type: BulletedListBlockKeys.type,
    attributes: {
      BulletedListBlockKeys.delta:
          (delta ?? (Delta()..insert(text ?? ''))).toJson(),
      if (attributes != null) ...attributes,
      if (textDirection != null)
        BulletedListBlockKeys.textDirection: textDirection,
    },
    children: children ?? [],
  );
}

class BulletedListBlockComponentBuilder extends BlockComponentBuilder {
  BulletedListBlockComponentBuilder({
    super.configuration,
    this.iconBuilder,
  });

  final BlockIconBuilder? iconBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return BulletedListBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      iconBuilder: iconBuilder,
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
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class BulletedListBlockComponentWidget extends BlockComponentStatefulWidget {
  const BulletedListBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.iconBuilder,
  });

  final BlockIconBuilder? iconBuilder;

  @override
  State<BulletedListBlockComponentWidget> createState() =>
      _BulletedListBlockComponentWidgetState();
}

class _BulletedListBlockComponentWidgetState
    extends State<BulletedListBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: BulletedListBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

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
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final markdownPrefixLength = widget
        .node.attributes[BulletedListBlockKeys.markdownPrefixLength] as int?;

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        textDirection: textDirection,
        children: [
          // 生の`- `/`* `をテキスト側に表示している間（カーソルがこの行に
          // ある間）は、記号アイコンとの二重表示を避けるため隠す
          // （2026-09-26追加、DaiDai側の対応）。
          if (!(markdownPrefixLength != null && _isFocused))
            widget.iconBuilder != null
                ? widget.iconBuilder!(context, node)
                : _BulletedListIcon(
                    node: widget.node,
                    textStyle: textStyleWithTextSpan(),
                  ),
          Flexible(
            child: AppFlowyRichText(
              key: forwardKey,
              delegate: this,
              node: widget.node,
              editorState: editorState,
              // 非フォーカス時に描画から外しているプレフィックスの長さ
              // （2026-10-04追加。座標計算をDeltaのオフセットへ換算する）。
              hiddenPrefixLength: hiddenMarkdownPrefixLength(
                node: widget.node,
                prefixLength: markdownPrefixLength,
                isFocused: _isFocused,
              ),
              textAlign: alignment?.toTextAlign ?? textAlign,
              placeholderText: placeholderText,
              textSpanDecorator: (textSpan) {
                final result = textSpan.updateTextStyle(
                  textStyleWithTextSpan(textSpan: textSpan),
                );
                // 2026-09-26追加、DaiDai側の対応。非フォーカス時は記号
                // アイコンと二重に幅を取らないよう`omitPrefixWhenHidden`を
                // 指定する（2026-09-27修正、`markdown_prefix_reveal.dart`参照）。
                return hideMarkdownPrefixWhenNotFocused(
                  textSpan: result,
                  prefixLength: markdownPrefixLength,
                  isFocused: _isFocused,
                  omitPrefixWhenHidden: true,
                );
              },
              placeholderTextSpanDecorator: (textSpan) =>
                  textSpan.updateTextStyle(
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

    child = Container(
      decoration: withBackgroundColor ? decoration : null,
      key: blockComponentKey,
      padding: padding,
      child: child,
    );

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
}

class _BulletedListIcon extends StatelessWidget {
  const _BulletedListIcon({
    required this.node,
    required this.textStyle,
  });

  final Node node;
  final TextStyle textStyle;

  static final bulletedListIcons = [
    '●',
    '◯',
    '□',
  ];

  int get level {
    var level = 0;
    var parent = node.parent;
    while (parent != null) {
      if (parent.type == 'bulleted_list') {
        level++;
      }
      parent = parent.parent;
    }
    return level;
  }

  String get icon => bulletedListIcons[level % bulletedListIcons.length];

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final textScaleFactor = editorState.editorStyle.textScaleFactor;
    // 本文（`AppFlowyRichText`）と同じ`height`/`TextHeightBehavior`を
    // アイコン側にも適用し、上下位置のずれを無くす（2026-09-27修正）。
    final textStyleConfiguration =
        editorState.editorStyle.textStyleConfiguration;
    return Container(
      constraints:
          const BoxConstraints(minWidth: 26, minHeight: 22) * textScaleFactor,
      padding: const EdgeInsets.only(right: 4.0),
      child: Center(
        child: Text(
          icon,
          style: textStyle.copyWith(height: textStyleConfiguration.lineHeight),
          textScaler: TextScaler.linear(0.5 * textScaleFactor),
          textHeightBehavior: TextHeightBehavior(
            applyHeightToFirstAscent:
                textStyleConfiguration.applyHeightToFirstAscent,
            applyHeightToLastDescent:
                textStyleConfiguration.applyHeightToLastDescent,
            leadingDistribution: textStyleConfiguration.leadingDistribution,
          ),
        ),
      ),
    );
  }
}
