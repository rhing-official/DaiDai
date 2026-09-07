import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note.dart';

/// 共有ノート機能のRepository（2026-09-06追加）。`PollRepository`と同じく
/// 「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した薄い実装。
///
/// v1は単独保存（後勝ち）方式のため、[updateNote]は常にフルドキュメント
/// 上書きに徹する（将来リアルタイム共同編集に拡張する際、部分パッチ適用用の
/// メソッドを追加しやすいよう責務を分けている）。
abstract class NoteRepository {
  Stream<List<Note>> watchNotes({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  /// 1件をライブ購読する（チャット上の通知カード表示用、2026-09-07追加）。
  /// タイトルが後から編集されても表示が追従するようにするため
  /// （`chat_screen.dart`の`_noteCreatedNoticeContent`参照）。
  Stream<Note?> watchNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  });

  /// 単発で1件だけ取得する（エディタを開く際の初期読み込み用。v1は開いた
  /// 時点の内容を読み込むだけでよく、編集中に他人の更新をライブ反映する
  /// 必要は無い）。
  Future<Note?> getNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  });

  /// 空の本文でノートを作成する（「+」ボタンから即座に呼ばれ、そのまま
  /// エディタへ遷移する。投票のようなフォームダイアログを介さない）。
  Future<Note> createNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String createdBy,
    String title = '',
  });

  /// フルドキュメント上書き保存。[updatedAt]/[lastEditedBy]も同時更新する。
  Future<void> updateNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required String title,
    required Map<String, dynamic> content,
    required String editedBy,
  });

  /// 作成者のみ削除可能（firestore.rules参照）。
  Future<void> deleteNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  });
}

class FirestoreNoteRepository implements NoteRepository {
  FirestoreNoteRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _roomsCollection(
    bool isDm,
    String conversationId,
  ) {
    final topLevel = isDm ? 'directMessages' : 'groups';
    return _firestore
        .collection(topLevel)
        .doc(conversationId)
        .collection('rooms');
  }

  CollectionReference<Map<String, dynamic>> _notesCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).collection('notes');
  }

  DocumentReference<Map<String, dynamic>> _noteRef({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) {
    return _notesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(noteId);
  }

  @override
  Stream<List<Note>> watchNotes({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _notesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Note.fromJson(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Stream<Note?> watchNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) {
    return _noteRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return Note.fromJson(doc.id, data);
    });
  }

  @override
  Future<Note?> getNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) async {
    final doc = await _noteRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).get();
    final data = doc.data();
    if (data == null) return null;
    return Note.fromJson(doc.id, data);
  }

  @override
  Future<Note> createNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String createdBy,
    String title = '',
  }) async {
    final ref = _notesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final note = Note(
      noteId: ref.id,
      roomId: roomId,
      title: title,
      content: const {},
      createdBy: createdBy,
    );
    await ref.set(note.toJson());
    return note;
  }

  @override
  Future<void> updateNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required String title,
    required Map<String, dynamic> content,
    required String editedBy,
  }) {
    return _noteRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).update({
      'title': title,
      'content': content,
      'lastEditedBy': editedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) {
    return _noteRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).delete();
  }
}
