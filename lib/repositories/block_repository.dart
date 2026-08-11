import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対の相手をブロックする機能を扱うリポジトリ。ブロック一覧は本人のみが
/// 読み書きできる完全に個人的な設定（[ConversationPrefsRepository]と同じ方針）。
abstract class BlockRepository {
  /// 自分がブロックした相手のuserId一覧を購読する（一対の表示・送信抑制用）。
  Stream<Set<String>> watchBlockedUserIds(String userId);

  Future<void> block({required String userId, required String targetUserId});

  Future<void> unblock({required String userId, required String targetUserId});
}

class FirestoreBlockRepository implements BlockRepository {
  FirestoreBlockRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _blockedUsersOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('blockedUsers');

  @override
  Stream<Set<String>> watchBlockedUserIds(String userId) {
    return _blockedUsersOf(
      userId,
    ).snapshots().map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  @override
  Future<void> block({
    required String userId,
    required String targetUserId,
  }) async {
    await _blockedUsersOf(
      userId,
    ).doc(targetUserId).set({'blockedAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> unblock({
    required String userId,
    required String targetUserId,
  }) async {
    await _blockedUsersOf(userId).doc(targetUserId).delete();
  }
}
