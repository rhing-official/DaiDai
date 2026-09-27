import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/markdown_prefix_reveal.dart';

const _kBulletedListItemId = 'editor.bulleted_list';

final ToolbarItem bulletedListItem = ToolbarItem(
  id: _kBulletedListItemId,
  group: 3,
  isActive: onlyShowInTextType,
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection!;
    final node = editorState.getNodeAtPath(selection.start.path)!;
    final isHighlight = node.type == 'bulleted_list';
    final child = SVGIconItemWidget(
      iconName: 'toolbar/bulleted_list',
      isHighlight: isHighlight,
      highlightColor: highlightColor,
      iconColor: iconColor,
      onPressed: () => editorState.formatNode(
        selection,
        (node) {
          if (isHighlight) {
            return node.copyWith(type: ParagraphBlockKeys.type);
          }
          // ボタンで箇条書きに変換した場合も、`- `入力による変換と同じように
          // 先頭記号を保持する（2026-09-27修正、DaiDai側の対応。
          // heading_toolbar_items.dartと同じ理由）。
          final prefixed = applyMarkdownPrefix(
            existingDelta: node.delta ?? Delta(),
            existingMarkdownPrefixLength: node
                .attributes[BulletedListBlockKeys.markdownPrefixLength] as int?,
            prefix: '- ',
          );
          return node.copyWith(
            type: BulletedListBlockKeys.type,
            attributes: {
              BulletedListBlockKeys.markdownPrefixLength:
                  prefixed.markdownPrefixLength,
              blockComponentDelta: prefixed.delta.toJson(),
            },
          );
        },
      ),
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        _kBulletedListItemId,
        AppFlowyEditorL10n.current.bulletedList,
        child,
      );
    }

    return child;
  },
);
