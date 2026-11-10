import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/message.dart';
import '../models/scheduled_message.dart';

/// 送信予定（`scheduledMessages`）の一覧・日時の変更・取り消し（2026-11-10追加）。
/// 予定の作成は、メッセージの組み立てと一緒に`DirectMessageRepository`・`GroupRepository`の
/// 送信メソッド（`sendAt`指定）が行う。
abstract class ScheduledMessageRepository {
  /// 自分が予定した、その寄合の送信予定（送信時刻の早い順）。
  Stream<List<ScheduledMessage>> watch({
    required String userId,
    required String conversationId,
    required String roomId,
  });

  /// 日時だけを変更する（送信待ちのみ）。
  Future<void> reschedule(String id, DateTime sendAt);

  /// 取り消す。添付があればStorageのファイルも消す。
  Future<void> cancel(ScheduledMessage scheduled);
}

class FirestoreScheduledMessageRepository
    implements ScheduledMessageRepository {
  FirestoreScheduledMessageRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('scheduledMessages');

  @override
  Stream<List<ScheduledMessage>> watch({
    required String userId,
    required String conversationId,
    required String roomId,
  }) {
    // `createdBy`で絞る（ルールと同じ条件が無いと`list`が拒否される）。
    return _col
        .where('createdBy', isEqualTo: userId)
        .where('conversationId', isEqualTo: conversationId)
        .where('roomId', isEqualTo: roomId)
        .orderBy('sendAt')
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              ScheduledMessage.fromJson(doc.id, doc.data()),
          ],
        );
  }

  @override
  Future<void> reschedule(String id, DateTime sendAt) {
    return _col.doc(id).update({'sendAt': Timestamp.fromDate(sendAt)});
  }

  @override
  Future<void> cancel(ScheduledMessage scheduled) async {
    await _col.doc(scheduled.id).delete();
    // 添付のファイルを片付ける（失敗しても取り消し自体は済んでいる）。
    final files = <MessageFileMetadata>[
      if (scheduled.message['attachments'] is List &&
          (scheduled.message['attachments'] as List).isNotEmpty)
        for (final a in scheduled.message['attachments'] as List)
          MessageFileMetadata.fromJson(Map<String, dynamic>.from(a as Map))
      else if (scheduled.message['fileMetadata'] is Map)
        MessageFileMetadata.fromJson(
          Map<String, dynamic>.from(scheduled.message['fileMetadata'] as Map),
        ),
    ];
    for (final file in files) {
      try {
        await _storage.refFromURL(file.url).delete();
      } catch (_) {}
    }
  }
}
