import 'package:appflowy_editor/appflowy_editor.dart';

/// Convert '* ' to bulleted list
///
/// - support
///   - desktop
///   - mobile
///   - web
///
CharacterShortcutEvent formatAsteriskToBulletedList = CharacterShortcutEvent(
  key: 'format asterisk to bulleted list',
  character: ' ',
  handler: (editorState) async =>
      await _formatSymbolToBulletedList(editorState, '*'),
);

/// Convert '- ' to bulleted list
///
/// - support
///   - desktop
///   - mobile
///   - web
///
CharacterShortcutEvent formatMinusToBulletedList = CharacterShortcutEvent(
  key: 'format minus to bulleted list',
  character: ' ',
  handler: (editorState) async =>
      await _formatSymbolToBulletedList(editorState, '-'),
);

/// Insert a new block after the bulleted list block.
///
/// - support
///   - desktop
///   - web
///   - mobile
///
CharacterShortcutEvent insertNewLineAfterBulletedList = CharacterShortcutEvent(
  key: 'insert new block after bulleted list',
  character: '\n',
  handler: (editorState) async => await insertNewLineInType(
    editorState,
    'bulleted_list',
  ),
);

// This function formats a symbol in the selection to a bulleted list.
// If the selection is not collapsed, it returns false.
// If the selection is collapsed and the text is not the symbol, it returns false.
// If the selection is collapsed and the text is the symbol, it will format the current node to a bulleted list.
Future<bool> _formatSymbolToBulletedList(
  EditorState editorState,
  String symbol,
) async {
  assert(symbol.length == 1);

  return formatMarkdownSymbol(
    editorState,
    (node) => node.type != BulletedListBlockKeys.type,
    (_, text, __) => text == symbol,
    (_, node, delta) => [
      node.copyWith(
        type: BulletedListBlockKeys.type,
        attributes: {
          // `-`/`*`を削除せず残し、消費されたトリガーのスペースを挿入する
          // （2026-09-26変更、DaiDai側の対応。`heading_character_shortcut
          // .dart`と同じ理由）。
          BulletedListBlockKeys.delta: delta
              .compose(Delta()
                ..retain(symbol.length)
                ..insert(' '))
              .toJson(),
          BulletedListBlockKeys.markdownPrefixLength: symbol.length + 1,
        },
      ),
    ],
    cursorOffset: (text) => text.length + 1,
  );
}
