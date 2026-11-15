import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../../models/app_ui_style.dart';
import '../../../providers/app_ui_style_provider.dart';
import '../../../widgets/copy_link_row.dart';

/// コードブロック（複数行）。Obsidianと同じく、カーソルが中にある間は上下に「```」の行を
/// 見せ、カーソルが外にある間は枠の右上にコピーボタンを出す。本文は他のテキストブロックと
/// 同じDelta（改行は`\n`の文字）。
class CodeBlockKeys {
  const CodeBlockKeys._();

  static const String type = 'daidai_code';
  static const String delta = blockComponentDelta;
}

Node codeBlockNode({Delta? delta}) {
  return Node(
    type: CodeBlockKeys.type,
    attributes: {'delta': (delta ?? Delta()).toJson()},
  );
}

/// コードブロックの中のEnterは、新しいブロックではなく`\n`を入れる。最後の行が空のまま
/// もう一度Enterを押したら、ブロックを抜けて下に段落を作る。
final CharacterShortcutEvent codeBlockNewLine = CharacterShortcutEvent(
  key: 'insert a new line in the code block',
  character: '\n',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null) return false;
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null || node.type != CodeBlockKeys.type) return false;
    if (!selection.isCollapsed) {
      await editorState.deleteSelection(selection);
    }
    final after = editorState.selection;
    if (after == null) return true;
    final delta = node.delta!;
    final text = delta.toPlainText();
    final offset = after.end.offset;
    final transaction = editorState.transaction;
    if (offset == text.length && text.endsWith('\n')) {
      // 空の最後の行でもう一度Enter: 余分な改行を消して、下に段落を作る。
      transaction
        ..deleteText(node, offset - 1, 1)
        ..insertNode(node.path.next, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: node.path.next));
    } else {
      transaction
        ..insertText(node, offset, '\n')
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: offset + 1),
        );
    }
    await editorState.apply(transaction);
    return true;
  },
);

class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
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
      (node) => node.delta != null;
}

class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: CodeBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  late final editorState = provider.Provider.of<EditorState>(
    context,
    listen: false,
  );

  bool _selectionInside(Selection? selection) =>
      selection != null && node.path.inSelection(selection);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final fenceStyle = TextStyle(
      fontFamily: 'monospace',
      color: scheme.onSurface.withValues(alpha: 0.45),
      height: 1.5,
    );

    final text = AppFlowyRichText(
      key: forwardKey,
      delegate: this,
      node: widget.node,
      editorState: editorState,
      textAlign: textAlign,
      placeholderText: placeholderText,
      textSpanDecorator: (textSpan) => textSpan.updateTextStyle(
        textStyleWithTextSpan(
          textSpan: textSpan,
        ).copyWith(fontFamily: 'monospace'),
      ),
      placeholderTextSpanDecorator: (textSpan) => textSpan.updateTextStyle(
        placeholderTextStyleWithTextSpan(textSpan: textSpan),
      ),
      textDirection: textDirection,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      cursorWidth: editorState.editorStyle.cursorWidth,
    );

    Widget child = ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, _) {
        final inside = _selectionInside(selection);
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(right: inside ? 0 : 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inside) Text('```', style: fenceStyle),
                    text,
                    if (inside) Text('```', style: fenceStyle),
                  ],
                ),
              ),
              if (!inside)
                Positioned(
                  top: 0,
                  right: 0,
                  // 他のコピーボタンと同じ部品（押すと弾み、少しの間✓になる）。
                  child: IconButtonTheme(
                    // ボタンを枠に収まる大きさにして、アイコンの周りに余白を持たせる。
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        fixedSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                      ),
                    ),
                    child: Consumer(
                      builder: (context, ref, _) => CopyIconButton(
                        gekiga:
                            ref.watch(appUiStyleProvider) == AppUiStyle.gekiga,
                        textBuilder: () => node.delta?.toPlainText() ?? '',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    child = Container(key: blockComponentKey, padding: padding, child: child);

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
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
