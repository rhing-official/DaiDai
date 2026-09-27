import 'package:appflowy_editor/appflowy_editor.dart';

import '../models/note.dart';

/// ノートの表示用タイトルを導出する（2026-09-07追加）。
///
/// タイトル欄が入力されていればそれを優先し、空ならNotion/Google Docs的に
/// 本文の先頭の非空行を暫定タイトルとして使う（タイトル欄への入力を強制
/// しないための救済）。どちらも空なら[fallback]を返す。「ある時点で確定
/// する」処理ではなく常に最新の内容から都度計算するだけなので、共有ノート
/// の共同編集（複数人が随時編集し続ける状態）とも矛盾しない
/// （`chat_screen.dart`の`_noteCreatedNoticeContent`・
/// `note_popup_content.dart`の`_NotePopupCard`で使う）。
String resolveNoteDisplayTitle(Note note, {required String fallback}) {
  final title = note.title.trim();
  if (title.isNotEmpty) return title;
  if (note.content.isEmpty) return fallback;
  try {
    final document = Document.fromJson(note.content);
    for (final node in document.root.children) {
      final text = plainTextWithoutMarkdownPrefix(node).trim();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {
    // 壊れた/未知形式のcontentは無視してfallbackへ。
  }
  return fallback;
}

/// 見出し/箇条書きに変換済みのノードは、生の`#`/`-`をDeltaに保持したまま
/// カーソル行のみ表示する（`markdown_prefix_reveal.dart`参照、2026-09-26
/// 追加）。表示用テキストにはこの先頭記号を含めない（2026-09-27、目次機能
/// からも再利用するため公開関数に変更）。
String plainTextWithoutMarkdownPrefix(Node node) {
  final text = node.delta?.toPlainText() ?? '';
  final prefixLength = switch (node.type) {
    HeadingBlockKeys.type =>
      node.attributes[HeadingBlockKeys.markdownPrefixLength] as int?,
    BulletedListBlockKeys.type =>
      node.attributes[BulletedListBlockKeys.markdownPrefixLength] as int?,
    _ => null,
  };
  if (prefixLength == null || prefixLength > text.length) return text;
  return text.substring(prefixLength);
}
