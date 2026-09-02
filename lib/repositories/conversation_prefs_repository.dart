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

  /// 語らいを開いて既読を付けたタイミングで、その時刻を記録する
  /// （語らい一覧の「未読優先」並べ替え用、2026-09-02追加）。
  Future<void> setLastRead({
    required String userId,
    required String conversationId,
  });

  /// 広場の寄合ごとの通知オフを設定する（`Room.customSettingsEnabled`が
  /// trueの間のみ有効、2026-07-29追加）。
  Future<void> setRoomNotificationsMuted({
    required String userId,
    required String conversationId,
    required String roomId,
    required bool muted,
  });

  /// 寄合単位のメッセージ入力欄の下書きを保存する（複数端末同期、
  /// 2026-08-13追加）。[draft]が空文字列ならそのキー自体を削除する
  /// （下書きが空になったら残さない）。
  Future<void> setDraft({
    required String userId,
    required String conversationId,
    required String roomId,
    required String draft,
  });
}

class FirestoreConversationPrefsRepository
    implements ConversationPrefsRepository {
  FirestoreConversationPrefsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _prefsOf(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('conversationPrefs');

  @override
  Stream<Map<String, ConversationPrefs>> watchAll(String userId) {
    return _prefsOf(userId).snapshots().map(
      (snapshot) => {
        for (final doc in snapshot.docs)
          doc.id: ConversationPrefs.fromJson(doc.data()),
      },
    );
  }

  @override
  Future<void> setPinned({
    required String userId,
    required String conversationId,
    required bool pinned,
  }) async {
    await _prefsOf(
      userId,
    ).doc(conversationId).set({'pinned': pinned}, SetOptions(merge: true));
  }

  @override
  Future<void> setNotificationsMuted({
    required String userId,
    required String conversationId,
    required bool muted,
  }) async {
    await _prefsOf(userId).doc(conversationId).set({
      'notificationsMuted': muted,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setLastRead({
    required String userId,
    required String conversationId,
  }) async {
    // unreadCountもここで0にリセットする（2026-09-02追加）。加算側は
    // Cloud Functions（functions/src/index.tsの`incrementUnreadCounts`）が
    // 相手からのメッセージ受信時に行うが、自分の既読はここで直接0に戻して
    // よい（本人による自分自身のconversationPrefsへの書き込みのため
    // firestore.rules上も許可される）。
    await _prefsOf(userId).doc(conversationId).set({
      'lastReadAt': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setRoomNotificationsMuted({
    required String userId,
    required String conversationId,
    required String roomId,
    required bool muted,
  }) async {
    await _prefsOf(userId).doc(conversationId).set({
      'roomNotificationOverrides': {roomId: muted},
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setDraft({
    required String userId,
    required String conversationId,
    required String roomId,
    required String draft,
  }) async {
    // set()はupdate()と異なりドット区切りキーをネストしたフィールドパスとして
    // 解釈しない（`cloud_firestore`の`DocumentReference.set`は
    // `_CodecUtility.replaceValueWithDelegatesInMap`を使い、`update`の
    // `...InMapFieldPath`とは別経路）。そのため`'draftByRoom.$roomId'`という
    // キーは`draftByRoom`マップの中ではなく、文字通りドットを含む無関係な
    // 最上位フィールドを作ってしまい、下書きが一切保存されていなかった
    // （2026-08-20発覚）。`setRoomNotificationsMuted`と同じネストした
    // マップリテラルに直し、`merge: true`の再帰マージで該当roomIdキーだけを
    // 更新する。
    await _prefsOf(userId).doc(conversationId).set({
      'draftByRoom': {roomId: draft.isEmpty ? FieldValue.delete() : draft},
    }, SetOptions(merge: true));
  }
}
