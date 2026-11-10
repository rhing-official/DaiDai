import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show ValueChanged;

import '../models/message.dart';
import '../utils/attachment_upload.dart';
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

  /// 予約の中身（文字・添付）を直す。[kept]は残す既存の添付、[added]は新しく足す添付
  /// （アップロードする）。添付が0件なら文字だけのメッセージ、1件なら単独の添付、2件以上なら
  /// 複数添付にする。外した添付はStorageからも消す。文字と添付が両方空なら`ArgumentError`。
  Future<void> updateContent(
    ScheduledMessage scheduled, {
    required String text,
    required List<MessageFileMetadata> kept,
    required List<AttachmentUploadInput> added,
    ValueChanged<double>? onProgress,
  });

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
  Future<void> updateContent(
    ScheduledMessage scheduled, {
    required String text,
    required List<MessageFileMetadata> kept,
    required List<AttachmentUploadInput> added,
    ValueChanged<double>? onProgress,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && kept.isEmpty && added.isEmpty) {
      throw ArgumentError('文字も添付も空です');
    }
    if (kept.length + added.length > kMaxMultiAttachments) {
      throw ArgumentError('添付が多すぎます');
    }
    final prefix = scheduled.scope == 'dm'
        ? 'dmFiles/${scheduled.conversationId}'
        : 'groupFiles/${scheduled.conversationId}';
    // 新しい添付をアップロードする（途中で失敗したら、アップロード済み分を片付けて投げる）。
    final uploaded = added.isEmpty
        ? const <MessageFileMetadata>[]
        : await uploadMultiMessageAttachments(
            storage: _storage,
            storagePathPrefix: prefix,
            messageId:
                '${scheduled.messageId}/e${DateTime.now().millisecondsSinceEpoch}',
            items: added,
            onProgress: onProgress,
          );
    final files = [...kept, ...uploaded];
    final message = Map<String, dynamic>.from(scheduled.message);
    String lastType;
    String? preview;
    if (files.isEmpty) {
      message
        ..['contentType'] = 'text'
        ..['content'] = trimmed
        ..['fileMetadata'] = null
        ..['attachments'] = <Map<String, dynamic>>[]
        ..remove('caption');
      lastType = 'text';
      preview = messageSnippetOf(trimmed);
    } else {
      if (files.length == 1) {
        final f = files.first;
        lastType = f.isImage ? 'image' : (f.isVideo ? 'video' : 'file');
        message
          ..['contentType'] = lastType
          ..['content'] = f.fileName
          ..['fileMetadata'] = f.toJson()
          ..['attachments'] = <Map<String, dynamic>>[];
      } else {
        lastType = 'multi';
        message
          ..['contentType'] = 'multi'
          ..['content'] = multiAttachmentContent(files)
          ..['fileMetadata'] = files.first.toJson()
          ..['attachments'] = [for (final f in files) f.toJson()];
      }
      if (trimmed.isEmpty) {
        message.remove('caption');
      } else {
        message['caption'] = trimmed;
      }
      preview = null;
    }
    final keptUrls = {for (final f in kept) f.url};
    try {
      await _col.doc(scheduled.id).update({
        'message': message,
        'lastMessageContentType': lastType,
        'lastMessagePreview': preview,
      });
    } catch (_) {
      for (final f in uploaded) {
        try {
          await _storage.refFromURL(f.url).delete();
        } catch (_) {}
      }
      rethrow;
    }
    // 外した添付のファイルを片付ける（失敗しても更新自体は済んでいる）。
    for (final old in scheduled.files) {
      if (keptUrls.contains(old.url)) continue;
      try {
        await _storage.refFromURL(old.url).delete();
      } catch (_) {}
    }
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
