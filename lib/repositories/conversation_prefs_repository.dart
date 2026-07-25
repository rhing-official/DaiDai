import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/conversation_prefs.dart';

/// 一対・広場のピン留め・通知オフといった、個人的な表示設定を扱うリポジトリ。
abstract class ConversationPrefsRepository {
  /// 自分の全conversationPrefsを一括で購読する（一覧のソート・アイコン表示用）。
  Stream<Map<String, ConversationPrefs>> watchAll(String userId);

  Future<void> setPinned({
    required String userId,
    required String conversationId,
    required bool pinned,
  });

  Future<void> setNotificationsMuted({
    required String userId,
    required String conversationId,
    required bool muted,
  });

  Future<void> setReadReceiptsEnabled({
    required String userId,
    required String conversationId,
    required bool enabled,
  });
}

class FirestoreConversationPrefsRepository implements ConversationPrefsRepository {
  FirestoreConversationPrefsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _prefsOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('conversationPrefs');

  @override
  Stream<Map<String, ConversationPrefs>> watchAll(String userId) {
    return _prefsOf(userId).snapshots().map((snapshot) => {
          for (final doc in snapshot.docs)
            doc.id: ConversationPrefs.fromJson(doc.data()),
        });
  }

  @override
  Future<void> setPinned({
    required String userId,
    required String conversationId,
    required bool pinned,
  }) async {
    await _prefsOf(userId)
        .doc(conversationId)
        .set({'pinned': pinned}, SetOptions(merge: true));
  }

  @override
  Future<void> setNotificationsMuted({
    required String userId,
    required String conversationId,
    required bool muted,
  }) async {
    await _prefsOf(userId)
        .doc(conversationId)
        .set({'notificationsMuted': muted}, SetOptions(merge: true));
  }

  @override
  Future<void> setReadReceiptsEnabled({
    required String userId,
    required String conversationId,
    required bool enabled,
  }) async {
    await _prefsOf(userId)
        .doc(conversationId)
        .set({'readReceiptsEnabled': enabled}, SetOptions(merge: true));
  }
}
