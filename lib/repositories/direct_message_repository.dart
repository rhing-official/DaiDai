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

  /// 指定したメッセージ群に、自分（[userId]）が読んだ記録を追加する。
  Future<void> markMessagesRead({
    required String dmId,
    required String userId,
    required List<String> messageIds,
  });

  /// 絶縁（友達関係の解消・会話履歴の完全削除）を提案し、相手の同意待ちにする。
  Future<void> proposeSeverance({required String dmId, required String userId});

  /// 絶縁の提案を取り消す（自分が提案した場合）、または辞退する（相手からの
  /// 提案に同意しない場合）。どちらも同じくフラグをクリアするだけ。
  Future<void> cancelSeverance(String dmId);

  /// 相手からの絶縁の提案に同意し、実際に絶縁を実行する。全メッセージ・
  /// 双方のfriends関係・friendRequests・この一対自体を物理削除する
  /// （復元不可）。[proposeSeverance]した本人以外の参加者のみ呼べる
  /// （Firestoreルールで強制、詳細はfirestore.rules参照）。
  Future<void> acceptSeverance({
    required String dmId,
    required String currentUserId,
    required String otherUserId,
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

  @override
  Future<void> markMessagesRead({
    required String dmId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final messagesRef = _directMessages.doc(dmId).collection('messages');
    final batch = _firestore.batch();
    // FieldValue.serverTimestamp()は配列要素の中では使えない（nullになる）ため、
    // クライアント側の時刻をそのまま記録する。
    final readAt = Timestamp.now();
    for (final messageId in messageIds) {
      batch.update(messagesRef.doc(messageId), {
        'readBy': FieldValue.arrayUnion([
          {'userId': userId, 'readAt': readAt},
        ]),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> proposeSeverance({
    required String dmId,
    required String userId,
  }) async {
    await _directMessages.doc(dmId).update({'severanceRequestedBy': userId});
  }

  @override
  Future<void> cancelSeverance(String dmId) async {
    await _directMessages.doc(dmId).update({'severanceRequestedBy': null});
  }

  @override
  Future<void> acceptSeverance({
    required String dmId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    final dmRef = _directMessages.doc(dmId);
    final messagesRef = dmRef.collection('messages');

    // Firestoreの1バッチは500件までのため、無くなるまでページ単位で削除を
    // 繰り返す。DMドキュメント自体（severanceRequestedByフラグ）はこの間
    // 消さずに残しておく必要がある（各messageのdeleteルールがこのフラグを
    // 参照して双方合意済みかどうかを検証するため）。
    while (true) {
      final snapshot = await messagesRef.limit(400).get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    final cascadeBatch = _firestore.batch();
    cascadeBatch.delete(
      _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .doc(otherUserId),
    );
    cascadeBatch.delete(
      _firestore
          .collection('users')
          .doc(otherUserId)
          .collection('friends')
          .doc(currentUserId),
    );
    // friendRequestsのidはdirectMessagesのdmIdと同じ組み立て方（pairId）の
    // ため、同じdmIdでそのままドキュメントを特定できる。
    cascadeBatch.delete(_firestore.collection('friendRequests').doc(dmId));
    await cascadeBatch.commit();

    // 一対自体は、上記すべての削除を許可する根拠（severanceRequestedBy）を
    // 持っているため、最後に削除する。
    await dmRef.delete();
  }
}
