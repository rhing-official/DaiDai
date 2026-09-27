import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/markdown_prefix_reveal.dart';

List<ToolbarItem> headingItems = [1, 2, 3]
    .map((index) => _HeadingToolbarItem(index))
    .toList(growable: false);

class _HeadingToolbarItem extends ToolbarItem {
  final int level;

  _HeadingToolbarItem(this.level)
      : super(
          id: 'editor.h$level',
          group: 1,
          isActive: onlyShowInSingleSelectionAndTextType,
          builder: (
            context,
            editorState,
            highlightColor,
            iconColor,
            tooltipBuilder,
          ) {
            final selection = editorState.selection!;
            final node = editorState.getNodeAtPath(selection.start.path)!;
            final isHighlight =
                node.type == 'heading' && node.attributes['level'] == level;
            final delta = (node.delta ?? Delta()).toJson();
            final child = SVGIconItemWidget(
              iconName: 'toolbar/h$level',
              isHighlight: isHighlight,
              highlightColor: highlightColor,
              iconColor: iconColor,
              onPressed: () => editorState.formatNode(
                selection,
                (node) {
                  if (isHighlight) {
                    return node.copyWith(
                      type: ParagraphBlockKeys.type,
                      attributes: {
                        blockComponentBackgroundColor:
                            node.attributes[blockComponentBackgroundColor],
                        blockComponentTextDirection:
                            node.attributes[blockComponentTextDirection],
                        blockComponentDelta: delta,
                      },
                    );
                  }
                  // ボタンで見出しに変換した場合も、`# `入力による変換と同じ
                  // ように先頭記号を保持する（2026-09-27修正、DaiDai側の
                  // 対応）。以前はここで`#`を一切挿入せず、カーソルを合わせても
                  // `#`が現れないという不一致があった。
                  final prefixed = applyMarkdownPrefix(
                    existingDelta: node.delta ?? Delta(),
                    existingMarkdownPrefixLength:
                        node.attributes[HeadingBlockKeys.markdownPrefixLength]
                            as int?,
                    prefix: '${'#' * level} ',
                  );
                  return node.copyWith(
                    type: HeadingBlockKeys.type,
                    attributes: {
                      HeadingBlockKeys.level: level,
                      HeadingBlockKeys.markdownPrefixLength:
                          prefixed.markdownPrefixLength,
                      blockComponentBackgroundColor:
                          node.attributes[blockComponentBackgroundColor],
                      blockComponentTextDirection:
                          node.attributes[blockComponentTextDirection],
                      blockComponentDelta: prefixed.delta.toJson(),
                    },
                  );
                },
              ),
            );

            if (tooltipBuilder != null) {
              return tooltipBuilder(
                context,
                'editor.h$level',
                levelToTooltips(level),
                child,
              );
            }

            return child;
          },
        );

  static String levelToTooltips(int level) {
    if (level == 1) {
      return AppFlowyEditorL10n.current.heading1;
    } else if (level == 2) {
      return AppFlowyEditorL10n.current.heading2;
    } else if (level == 3) {
      return AppFlowyEditorL10n.current.heading3;
    }
    return '';
  }
}
