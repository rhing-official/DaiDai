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
    Message? replyTo,
  });

  /// 通話が終了した際、通話履歴メッセージ（開始時刻・通話時間）を送る。
  /// 発信者側からのみ呼ばれる（`WebrtcCallController`参照）。実際に接続
  /// （応答）された通話のみが対象で、不在着信・拒否の場合は呼ばれない。
  Future<void> sendCallSummaryMessage({
    required String dmId,
    required String senderId,
    required String senderRhingId,
    required DateTime startedAt,
    required int durationSeconds,
    required bool isVideo,
  });

  /// 送信済みテキストメッセージの本文を編集する（本文編集のみ・時間制限なし）。
  Future<void> editMessage({
    required String dmId,
    required String messageId,
    required String newContent,
  });

  /// 自分が送ったメッセージを、相手側にも痕跡を残さず完全に削除する
  /// （物理削除）。このメッセージを引用返信している他のメッセージがあれば、
  /// それらのreplyTo系フィールドも同時にクリアする。
  Future<void> unsendMessage({
    required String dmId,
    required String messageId,
  });

  /// 自分のリアクションを設定・解除する（[emoji]がnullなら解除、
  /// 既に設定済みでも上書きで乗り換えられる）。
  Future<void> setReaction({
    required String dmId,
    required String messageId,
    required String userId,
    String? emoji,
  });

  /// 指定したメッセージ群に、自分（[userId]）が読んだ記録を追加する。
  Future<void> markMessagesRead({
    required String dmId,
    required String userId,
    required List<String> messageIds,
  });

  /// 選択したメッセージ群を、自分（[userId]）のアカウントから見えなくする
  /// （実際にはサーバーから削除せず、相手には引き続き見える）。会話履歴が
  /// 増えすぎた場合の整理を助ける機能。一対の参加者（2人）両方が同じ
  /// メッセージを削除し終えた時点で、この呼び出しの中でサーバーからも
  /// 物理削除する。
  Future<void> hideMessagesForMe({
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

  /// 既読機能のオン/オフの変更を提案する（一対共有の1つの設定。個人ごとの
  /// 非公開設定ではない）。提案は常に現在の値を反転させることを意味する。
  /// 相手が[acceptReadReceiptsToggle]で承認するまで反映されない。
  Future<void> proposeReadReceiptsToggle({
    required String dmId,
    required String userId,
  });

  /// 既読オン/オフの変更提案を取り消す（自分が提案した場合）、または
  /// 辞退する（相手からの提案に同意しない場合）。どちらも同じくフラグを
  /// クリアするだけ。
  Future<void> cancelReadReceiptsToggleProposal(String dmId);

  /// 相手からの既読オン/オフの変更提案に同意し、実際に反映する。オフに
  /// する提案だった場合は、続けてこの一対の全メッセージ・両参加者分の
  /// 既読履歴をサーバーから削除する。[proposeReadReceiptsToggle]した本人
  /// 以外の参加者のみ呼べる（firestore.rulesで強制）。
  Future<void> acceptReadReceiptsToggle({
    required String dmId,
    required String currentUserId,
  });

  /// アカウント削除通知メッセージの「いいえ」。以後はい/いいえボタンを
  /// 表示しないようにするだけで、他には何もしない。
  Future<void> declineAccountDeletionNotice({
    required String dmId,
    required String messageId,
  });

  /// アカウント削除通知メッセージの「はい」（確認ダイアログの上で呼ばれる）。
  /// 相手のアカウントが既に削除されている場合のみ実行できる
  /// （[DirectMessage.accountDeletedUserId]、firestore.rulesで強制）。
  /// この一対の全メッセージとドキュメント自体を物理削除する。
  Future<void> deleteDmAfterAccountDeletion(String dmId);
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
    Message? replyTo,
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
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null ? null : messageSnippetOf(replyTo.content),
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(dmRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> sendCallSummaryMessage({
    required String dmId,
    required String senderId,
    required String senderRhingId,
    required DateTime startedAt,
    required int durationSeconds,
    required bool isVideo,
  }) async {
    final dmRef = _directMessages.doc(dmId);
    final messageRef = dmRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: dmId,
      conversationType: 'dm',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: '通話が終了しました',
      contentType: 'call',
      callStartedAt: Timestamp.fromDate(startedAt),
      callDurationSeconds: durationSeconds,
      callIsVideo: isVideo,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(dmRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> editMessage({
    required String dmId,
    required String messageId,
    required String newContent,
  }) async {
    await _directMessages.doc(dmId).collection('messages').doc(messageId).update({
      'content': newContent,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unsendMessage({
    required String dmId,
    required String messageId,
  }) async {
    final messagesRef = _directMessages.doc(dmId).collection('messages');
    final quoting = await messagesRef
        .where('replyToMessageId', isEqualTo: messageId)
        .get();

    // 1件のメッセージへの引用返信が499件を超えることは現実的に想定しない
    // ため、500件のバッチ上限に収まる範囲でまとめて処理する
    // （本体の削除1件＋引用側の更新最大499件）。
    final batch = _firestore.batch();
    batch.delete(messagesRef.doc(messageId));
    for (final doc in quoting.docs.take(499)) {
      batch.update(doc.reference, {
        'replyToMessageId': FieldValue.delete(),
        'replyToSenderId': FieldValue.delete(),
        'replyToSenderRhingId': FieldValue.delete(),
        'replyToSnippet': FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> setReaction({
    required String dmId,
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    final ref = _directMessages.doc(dmId).collection('messages').doc(messageId);
    await ref.update({
      'reactions.$userId': emoji ?? FieldValue.delete(),
    });
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
  Future<void> hideMessagesForMe({
    required String dmId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final dmRef = _directMessages.doc(dmId);
    final dmSnapshot = await dmRef.get();
    final participants = List<String>.from(
      dmSnapshot.data()?['participants'] as List? ?? const [],
    );
    final messagesRef = dmRef.collection('messages');

    // 各メッセージの現在のhiddenForを確認し、自分を加えた結果が参加者
    // 全員をカバーするなら物理削除、そうでなければhiddenForに自分を追加する
    // 更新に留める（1件ずつgetするのは、Firestoreの`whereIn`が30件までの
    // 制約を持つため、選択件数に上限を設けずに済むようにするための選択）。
    final docs = await Future.wait(
      messageIds.map((id) => messagesRef.doc(id).get()),
    );

    // Firestoreの1バッチは500件までのため、chunk単位でコミットする。
    for (var i = 0; i < docs.length; i += 400) {
      final chunk = docs.sublist(i, i + 400 > docs.length ? docs.length : i + 400);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        if (!doc.exists) continue;
        final hiddenFor = {
          ...?(doc.data()?['hiddenFor'] as List?)?.cast<String>(),
          userId,
        };
        if (participants.every(hiddenFor.contains)) {
          batch.delete(doc.reference);
        } else {
          batch.update(doc.reference, {
            'hiddenFor': FieldValue.arrayUnion([userId]),
          });
        }
      }
      await batch.commit();
    }
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

  @override
  Future<void> proposeReadReceiptsToggle({
    required String dmId,
    required String userId,
  }) async {
    await _directMessages.doc(dmId).update({'readReceiptsProposalBy': userId});
  }

  @override
  Future<void> cancelReadReceiptsToggleProposal(String dmId) async {
    await _directMessages.doc(dmId).update({'readReceiptsProposalBy': null});
  }

  @override
  Future<void> acceptReadReceiptsToggle({
    required String dmId,
    required String currentUserId,
  }) async {
    final dmRef = _directMessages.doc(dmId);
    final snapshot = await dmRef.get();
    final data = snapshot.data();
    final proposedBy = data?['readReceiptsProposalBy'] as String?;
    if (proposedBy == null || proposedBy == currentUserId) return;
    final newEnabled = !(data?['readReceiptsEnabled'] as bool? ?? true);
    await dmRef.update({
      'readReceiptsEnabled': newEnabled,
      'readReceiptsProposalBy': null,
    });
    if (!newEnabled) {
      await _clearAllReadReceipts(dmRef.collection('messages'));
    }
  }

  @override
  Future<void> declineAccountDeletionNotice({
    required String dmId,
    required String messageId,
  }) async {
    await _directMessages
        .doc(dmId)
        .collection('messages')
        .doc(messageId)
        .update({'accountDeletionResponse': 'declined'});
  }

  @override
  Future<void> deleteDmAfterAccountDeletion(String dmId) async {
    final dmRef = _directMessages.doc(dmId);
    final messagesRef = dmRef.collection('messages');

    // acceptSeveranceと同じページ単位の削除ループ（削除済みのdocは次回
    // 取得に現れないため.limit(400)の繰り返し取得で全件処理できる）。
    // friends/friendRequestsのカスケード削除は、アカウント削除処理
    // （Cloud Functions）が既に行っているためここでは不要。
    while (true) {
      final snapshot = await messagesRef.limit(400).get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await dmRef.delete();
  }

  /// [messagesRef]配下の全メッセージの既読履歴（readBy）を空にする。
  /// 更新後もドキュメントは残り続けるため、`acceptSeverance`の
  /// （削除により毎回別集合が返ってくる）`.limit(400)`繰り返し取得とは
  /// 異なり、カーソルで明示的にページを進める必要がある。
  Future<void> _clearAllReadReceipts(
    CollectionReference<Map<String, dynamic>> messagesRef,
  ) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      var query = messagesRef.orderBy(FieldPath.documentId).limit(400);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        final readBy = doc.data()['readBy'] as List<dynamic>? ?? const [];
        if (readBy.isNotEmpty) {
          batch.update(doc.reference, {'readBy': <Map<String, dynamic>>[]});
        }
      }
      await batch.commit();
      cursor = snapshot.docs.last;
      if (snapshot.docs.length < 400) break;
    }
  }
}
