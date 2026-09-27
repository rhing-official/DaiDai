import 'package:appflowy_editor/appflowy_editor.dart';

/// `# `/`- `/`* `＋末尾スペースというMarkdownショートカットのトリガー
/// パターン（2026-09-26追加、DaiDai側の対応）。
final _kMarkdownTriggerPrefix = RegExp(r'^(#{1,6}|[-*])$');

/// モバイルのIME（予測変換・自動修正）は、`# `のような複数文字を1回の
/// 入力イベント（[TextEditingDeltaInsertion.textInserted]/
/// [TextEditingDeltaReplacement.replacementText]）としてまとめて送って
/// くることがある。[executeCharacterShortcutEvent]は1文字のみを対象に
/// するため、このままではMarkdownショートカット（`# `→見出し等）が
/// 発火しない（2026-09-26修正、DaiDai側の対応）。
///
/// [text]が「既知のMarkdownトリガー文字列＋末尾スペース」の形（例:
/// `"# "`、`"### "`、`"- "`）に一致する場合のみ、スペースより前の部分と
/// 末尾のスペースに分割して返す。それ以外（通常の単語の確定入力等）は
/// nullを返し、呼び出し側は分割せずまとめて処理する（Undoの単位を
/// 無用に増やさないため、あくまでMarkdownトリガーらしい入力に限定する）。
(String prefix, String trigger)? splitTrailingMarkdownShortcutTrigger(
  String text,
) {
  if (text.length <= 1 || !text.endsWith(' ')) {
    return null;
  }
  final prefix = text.substring(0, text.length - 1);
  if (!_kMarkdownTriggerPrefix.hasMatch(prefix)) {
    return null;
  }
  return (prefix, ' ');
}

/// [text]をショートカット判定なしでそのまま現在のカーソル位置に挿入する
/// （2026-09-26追加、DaiDai側の対応）。
/// [splitTrailingMarkdownShortcutTrigger]で切り出した「トリガーより前の
/// 部分」を、まず通常のテキストとして挿入するために使う
/// （`delta_input_on_insert_impl.dart`/`delta_input_on_replace_impl.dart`
/// 参照）。
Future<void> insertPlainTextWithoutShortcutCheck(
  EditorState editorState,
  String text,
) async {
  var selection = editorState.selection;
  if (selection == null) {
    return;
  }
  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
  }
  selection = editorState.selection?.normalized;
  if (selection == null || !selection.isCollapsed) {
    return;
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) {
    return;
  }
  final newOffset = selection.startIndex + text.length;
  final transaction = editorState.transaction
    ..insertText(
      node,
      selection.startIndex,
      text,
      toggledAttributes: editorState.toggledStyle,
      sliceAttributes: editorState.sliceUpcomingAttributes,
    )
    ..afterSelection = Selection.collapsed(
      Position(path: node.path, offset: newOffset),
    );
  await editorState.apply(transaction);
}

Future<bool> executeCharacterShortcutEvent(
  EditorState editorState,
  String? character,
  List<CharacterShortcutEvent> characterShortcutEvents,
) async {
  // if the character is a space + enter, we should execute the enter event
  if (character == ' \n') {
    character = '\n';
  }

  if (character?.length != 1) {
    return false;
  }

  for (final shortcutEvent in characterShortcutEvents) {
    bool hasMatchRegExp = false;
    final regExp = shortcutEvent.regExp;
    if (regExp != null && character != null) {
      hasMatchRegExp = regExp.hasMatch(character);
      if (hasMatchRegExp &&
          shortcutEvent.handlerWithCharacter != null &&
          await shortcutEvent.executeWithCharacter(
            editorState,
            character,
          )) {
        AppFlowyEditorLog.input.debug(
          'keyboard service - handled by character shortcut event: $shortcutEvent',
        );
        return true;
      }
    }
    if ((shortcutEvent.character == character || hasMatchRegExp) &&
        await shortcutEvent.handler(editorState)) {
      AppFlowyEditorLog.input.debug(
        'keyboard service - handled by character shortcut event: $shortcutEvent',
      );
      return true;
    }
  }

  return false;
}
