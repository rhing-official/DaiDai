import 'package:cloud_firestore/cloud_firestore.dart';

/// 寄合単位の共有ノート（2026-09-06追加。`directMessages/{dmId}/rooms/{roomId}/
/// notes/{noteId}`または`groups/{groupId}/rooms/{roomId}/notes/{noteId}`）。
///
/// [content]はappflowy_editorの`Document.toJson()`をそのまま保存した構造化
/// データ（フラットなMarkdown文字列ではない）。v1は投票・日程調整と同じ
/// 「フルドキュメント上書き保存」方式（[NoteRepository.updateNote]参照）で、
/// 複数人が同時に開いた場合は後から保存した方が反映される。ノート自体は
/// 寄合の参加者/メンバー全員が編集できる「共有」ノートのため、更新は誰でも
/// 可能（削除のみ[createdBy]本人限定、firestore.rules参照）。
class Note {
  const Note({
    required this.noteId,
    required this.roomId,
    required this.title,
    required this.content,
    required this.createdBy,
    this.createdAt,
    this.lastEditedBy,
    this.updatedAt,
  });

  final String noteId;
  final String roomId;
  final String title;

  /// appflowy_editorの`Document.toJson()`。
  final Map<String, dynamic> content;
  final String createdBy;
  final Timestamp? createdAt;
  final String? lastEditedBy;
  final Timestamp? updatedAt;

  factory Note.fromJson(String noteId, Map<String, dynamic> json) {
    return Note(
      noteId: noteId,
      roomId: json['roomId'] as String,
      title: json['title'] as String? ?? '',
      content: (json['content'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as Timestamp?,
      lastEditedBy: json['lastEditedBy'] as String?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'title': title,
    'content': content,
    'createdBy': createdBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'lastEditedBy': lastEditedBy,
    'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
  };
}
