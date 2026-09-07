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
      final text = node.delta?.toPlainText().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
  } catch (_) {
    // 壊れた/未知形式のcontentは無視してfallbackへ。
  }
  return fallback;
}
