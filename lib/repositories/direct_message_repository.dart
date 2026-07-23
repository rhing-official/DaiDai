import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/direct_message.dart';
import '../models/message.dart';

abstract class DirectMessageRepository {
  /// 2人のuserから一対を取得する。無ければ作成する。
  Future<DirectMessage> getOrCreateDirectMessage(AppUser a, AppUser b);

  /// 自分が参加している一対一覧を、最終メッセージが新しい順に取得する。
  Stream<List<DirectMessage>> watchDirectMessages(String userId);

  Stream<List<Message>> watchMessages(String dmId);

  Future<void> sendTextMessage({
    required String dmId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
  });
}

class FirestoreDirectMessageRepository implements DirectMessageRepository {
  FirestoreDirectMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _directMessages =>
      _firestore.collection('directMessages');

  @override
  Future<DirectMessage> getOrCreateDirectMessage(AppUser a, AppUser b) async {
    final dmId = DirectMessage.idFor(a.userId, b.userId);
    final ref = _directMessages.doc(dmId);
    final doc = await ref.get();

    if (doc.exists) {
      return DirectMessage.fromJson(dmId, doc.data()!);
    }

    final dm = DirectMessage(
      dmId: dmId,
      participants: [a.userId, b.userId],
      participantRhingIds: {a.userId: a.rhingId, b.userId: b.rhingId},
    );
    await ref.set(dm.toJson());
    return dm;
  }

  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) {
    return _directMessages
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DirectMessage.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<Message>> watchMessages(String dmId) {
    return _directMessages
        .doc(dmId)
        .collection('messages')
        .where('deletedAt', isNull: true)
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Message.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> sendTextMessage({
    required String dmId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
  }) async {
    final dmRef = _directMessages.doc(dmId);
    final messageRef = dmRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: dmId,
      conversationType: 'dm',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: content,
      contentType: 'text',
      silent: silent,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(dmRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
