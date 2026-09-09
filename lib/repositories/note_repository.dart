import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note.dart';
import '../models/note_op.dart';

/// 共有ノート機能のRepository（2026-09-06追加）。`PollRepository`と同じく
/// 「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した薄い実装。
///
/// [updateNote]はフルドキュメント上書き専任で、リアルタイム共同編集
/// （2026-09-09追加）における「チェックポイント」保存として使う。実際の
/// リアルタイム反映は[appendNoteOp]/[watchNoteOpsSince]による操作ログ
/// （`notes/{noteId}/ops`）経由で行う（`note_pane_view.dart`参照）。
/// [pruneNoteOpsUpTo]はチェックポイント確定後に古い操作ログを間引く。
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

  /// [afterCreatedAt]（省略時は先頭から）より新しい操作ログを、生成順
  /// （createdAt昇順）でライブ購読する。エディタを開いた直後はチェックポイント
  /// （`Note.updatedAt`）以降のopsを一括で受け取り（＝追いつき）、その後は
  /// 新規追加分のみ流れてくる。
  Stream<List<NoteOp>> watchNoteOpsSince({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    Timestamp? afterCreatedAt,
  });

  /// ローカルの短いデバウンス窓内に発生した複数[transactions]を1回の書き込み
  /// にまとめて送信する。[sessionId]はエコー判定用（このノートを開いている
  /// 間だけ有効なランダムID）。
  Future<void> appendNoteOp({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required List<Map<String, dynamic>> transactions,
    required String sessionId,
    required String authorId,
  });

  /// [upToCreatedAtInclusive]以前の操作ログを削除する（チェックポイント確定後
  /// の間引き）。
  Future<void> pruneNoteOpsUpTo({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required Timestamp upToCreatedAtInclusive,
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

  CollectionReference<Map<String, dynamic>> _opsCollection({
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
    ).collection('ops');
  }

  @override
  Stream<List<NoteOp>> watchNoteOpsSince({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    Timestamp? afterCreatedAt,
  }) {
    Query<Map<String, dynamic>> query = _opsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).orderBy('createdAt');
    if (afterCreatedAt != null) {
      query = query.where('createdAt', isGreaterThan: afterCreatedAt);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => NoteOp.fromJson(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Future<void> appendNoteOp({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required List<Map<String, dynamic>> transactions,
    required String sessionId,
    required String authorId,
  }) {
    return _opsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).add({
      'transactions': transactions,
      'sessionId': sessionId,
      'authorId': authorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> pruneNoteOpsUpTo({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required Timestamp upToCreatedAtInclusive,
  }) async {
    final snapshot = await _opsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      noteId: noteId,
    ).where('createdAt', isLessThanOrEqualTo: upToCreatedAtInclusive).get();
    if (snapshot.docs.isEmpty) return;
    // WriteBatchは1バッチ500件上限のため分割する。
    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(450)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
