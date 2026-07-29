import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/direct_message.dart';
import '../models/dm_room.dart';
import '../models/message.dart';

abstract class DirectMessageRepository {
  /// 2人のuserから一対を取得する。無ければ作成する
  /// （既定の寄合「メイン」も同時に1件作る）。
  Future<DirectMessage> getOrCreateDirectMessage(AppUser a, AppUser b);

  /// 自分が参加している一対一覧を、最終メッセージが新しい順に取得する。
  Stream<List<DirectMessage>> watchDirectMessages(String userId);

  /// この一対の寄合（テキストチャンネル）一覧を作成順に購読する。[userId]は
  /// 呼び出し元本人のuserId（firestore.rulesの`list`操作はクエリ自体に
  /// ルールと同じ条件の`where`句が無いと要求全体を拒否するため、クエリ側にも
  /// `participants`のarray-contains条件を付ける必要がある。
  /// `GroupRepository.watchRooms`参照）。
  Stream<List<DmRoom>> watchRooms({required String dmId, required String userId});

  /// 新しい寄合を作成する（参加者ならどちらでも実行可能、確認不要）。
  Future<DmRoom> createRoom({required String dmId, required String name});

  /// 寄合の名前を変更する（参加者ならどちらでも実行可能）。
  Future<void> renameRoom({
    required String dmId,
    required String roomId,
    required String name,
  });

  /// 単一モードの一対を複数モードに切り替える（参加者ならどちらでも実行
  /// 可能）。複数→単一へ戻すことはできない（2026-07-29追加）。
  Future<void> setRoomsEnabled(String dmId);

  /// 寄合を削除する。全メッセージも物理削除する。この一対の最後の1つの
  /// 寄合は削除できない（[StateError]を投げる）。削除対象が
  /// [DirectMessage.defaultRoomId]の場合は、残った寄合のうち最も古い
  /// ものに`defaultRoomId`を差し替える。
  Future<void> deleteRoom({
    required String dmId,
    required String roomId,
    required String requestedBy,
  });

  Stream<List<Message>> watchMessages(String dmId, String roomId);

  /// [watchMessages]の直近50件に含まれない古い返信先へジャンプする際に使う。
  /// 指定した[messageId]を含む前後合わせて最大[contextSize]*2件を1回だけ
  /// 取得する（購読はしない）。対象メッセージが既に削除済みの場合は空を返す。
  Future<List<Message>> getMessagesAround({
    required String dmId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  });

  Future<void> sendTextMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
    Message? replyTo,
  });

  /// 通話が終了した際、通話履歴メッセージ（開始時刻・通話時間）を送る。
  /// 発信者側からのみ呼ばれる（`WebrtcCallController`参照）。実際に接続
  /// （応答）された通話のみが対象で、不在着信・拒否の場合は呼ばれない。
  /// 通話はどの寄合を開いていても発信できるため、常にこの一対の
  /// [DirectMessage.defaultRoomId]に投稿する（呼び出し側でroomIdを
  /// 意識させないための設計）。
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
    required String roomId,
    required String messageId,
    required String newContent,
  });

  /// 自分が送ったメッセージを、相手側にも痕跡を残さず完全に削除する
  /// （物理削除）。このメッセージを引用返信している他のメッセージがあれば、
  /// それらのreplyTo系フィールドも同時にクリアする。
  Future<void> unsendMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  });

  /// 自分のリアクションを設定・解除する（[emoji]がnullなら解除、
  /// 既に設定済みでも上書きで乗り換えられる）。
  Future<void> setReaction({
    required String dmId,
    required String roomId,
    required String messageId,
    required String userId,
    String? emoji,
  });

  /// 指定したメッセージ群に、自分（[userId]）が読んだ記録を追加する。
  Future<void> markMessagesRead({
    required String dmId,
    required String roomId,
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
    required String roomId,
    required String userId,
    required List<String> messageIds,
  });

  /// 絶縁（友達関係の解消・会話履歴の完全削除）を提案し、相手の同意待ちにする。
  Future<void> proposeSeverance({required String dmId, required String userId});

  /// 絶縁の提案を取り消す（自分が提案した場合）、または辞退する（相手からの
  /// 提案に同意しない場合）。どちらも同じくフラグをクリアするだけ。
  Future<void> cancelSeverance(String dmId);

  /// 相手からの絶縁の提案に同意し、実際に絶縁を実行する。全寄合・全メッセージ・
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
  /// する提案だった場合は、続けてこの一対の全寄合・両参加者分の既読履歴を
  /// サーバーから削除する。[proposeReadReceiptsToggle]した本人以外の
  /// 参加者のみ呼べる（firestore.rulesで強制）。
  Future<void> acceptReadReceiptsToggle({
    required String dmId,
    required String currentUserId,
  });

  /// アカウント削除通知メッセージの「いいえ」。以後はい/いいえボタンを
  /// 表示しないようにするだけで、他には何もしない。
  Future<void> declineAccountDeletionNotice({
    required String dmId,
    required String roomId,
    required String messageId,
  });

  /// アカウント削除通知メッセージの「はい」（確認ダイアログの上で呼ばれる）。
  /// 相手のアカウントが既に削除されている場合のみ実行できる
  /// （[DirectMessage.accountDeletedUserId]、firestore.rulesで強制）。
  /// この一対の全寄合・全メッセージとドキュメント自体を物理削除する。
  /// [userId]は呼び出し元本人のuserId（`rooms`サブコレクションの
  /// 絞り込み無し`.get()`が`list`操作としてfirestore.rulesにpermission-denied
  /// される問題を避けるため、`DirectMessageRepository.watchRooms`と同じ
  /// 理由で必要。他の`rooms`一括操作系メソッド全般に共通する制約）。
  Future<void> deleteDmAfterAccountDeletion(String dmId, {required String userId});
}

class FirestoreDirectMessageRepository implements DirectMessageRepository {
  FirestoreDirectMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _directMessages =>
      _firestore.collection('directMessages');

  DocumentReference<Map<String, dynamic>> _dmRoomRef(
    String dmId,
    String roomId,
  ) {
    return _directMessages.doc(dmId).collection('rooms').doc(roomId);
  }

  @override
  Future<DirectMessage> getOrCreateDirectMessage(AppUser a, AppUser b) async {
    final dmId = DirectMessage.idFor(a.userId, b.userId);
    final ref = _directMessages.doc(dmId);
    final doc = await ref.get();

    if (doc.exists) {
      final data = doc.data()!;
      if (data['defaultRoomId'] != null) {
        return DirectMessage.fromJson(dmId, data);
      }
      // 複数寄合機能移行時（migrateDirectMessagesToRoomsOnce、実行後ソースから
      // 削除済み）は、当時メッセージが1件も無かった一対を移行対象から漏らして
      // おり、defaultRoomId未設定のまま取り残されたドキュメントが存在した
      // （一対の一覧が丸ごと表示されなくなる不具合の原因、watchDirectMessages
      // 参照）。ここで気付いた時点で「メイン」寄合を作って補修する。
      final repairedRoomRef = ref.collection('rooms').doc();
      final existingParticipants = List<String>.from(
        data['participants'] as List? ?? [a.userId, b.userId],
      );
      final repairedRoom = DmRoom(
        roomId: repairedRoomRef.id,
        dmId: dmId,
        name: 'メイン',
        participants: existingParticipants,
      );
      await repairedRoomRef.set(repairedRoom.toJson());
      await ref.update({'defaultRoomId': repairedRoomRef.id});
      return DirectMessage.fromJson(dmId, {...data, 'defaultRoomId': repairedRoomRef.id});
    }

    final roomRef = ref.collection('rooms').doc();
    final participants = [a.userId, b.userId];
    final dm = DirectMessage(
      dmId: dmId,
      participants: participants,
      participantRhingIds: {a.userId: a.rhingId, b.userId: b.rhingId},
      defaultRoomId: roomRef.id,
      // 一対は常に単一モードで作られる（FriendRepository.respondと同じ、
      // 2026-07-29追加）。
      roomsEnabled: false,
    );
    final room = DmRoom(
      roomId: roomRef.id,
      dmId: dmId,
      name: 'メイン',
      participants: participants,
    );

    final batch = _firestore.batch();
    batch.set(ref, dm.toJson());
    batch.set(roomRef, room.toJson());
    await batch.commit();
    return dm;
  }

  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) {
    // watchRoomsと同じ理由でorderBy('lastMessageAt')は使わない。まだ
    // メッセージを1件も送っていない作成直後の一対はlastMessageAtが
    // 常にnullのままのため、orderByを付けるとFirestoreのクエリ結果から
    // 恒久的に除外され、一対の一覧に一切表示されなくなってしまっていた。
    return _directMessages
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final dms = <DirectMessage>[];
      for (final doc in snapshot.docs) {
        try {
          dms.add(DirectMessage.fromJson(doc.id, doc.data()));
        } catch (_) {
          // defaultRoomId未設定など、過去の移行漏れで不完全なドキュメントが
          // 混ざっていても一覧全体を巻き込まないよう、その1件だけ読み飛ばす
          // （getOrCreateDirectMessageが次に開かれた際に自己修復する）。
        }
      }
      dms.sort((a, b) => (b.lastMessageAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.lastMessageAt?.millisecondsSinceEpoch ?? 0));
      return dms;
    });
  }

  @override
  Stream<List<DmRoom>> watchRooms({required String dmId, required String userId}) {
    // Firestoreの`orderBy`はソート対象フィールドを持たないドキュメントを
    // 結果から除外してしまう（作成直後、serverTimestamp()がサーバー側で
    // 解決するまでの一瞬もローカルではcreatedAt=null扱いになり同様に除外
    // される）。`GroupRepository.watchRooms`と同じくクライアント側ソート
    // に変更して回避する。
    //
    // where('participants', arrayContains: userId)はfirestore.rulesの`list`
    // 要求を満たすために必須（`GroupRepository.watchRooms`のコメント参照）。
    return _directMessages
        .doc(dmId)
        .collection('rooms')
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final rooms =
          snapshot.docs.map((doc) => DmRoom.fromJson(doc.id, doc.data())).toList()
            ..sort((a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0)
                .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0));
      return rooms;
    });
  }

  @override
  Future<DmRoom> createRoom({
    required String dmId,
    required String name,
  }) async {
    final dmDoc = await _directMessages.doc(dmId).get();
    final participants = List<String>.from(
      dmDoc.data()?['participants'] as List? ?? const [],
    );
    final roomRef = _directMessages.doc(dmId).collection('rooms').doc();
    final room = DmRoom(
      roomId: roomRef.id,
      dmId: dmId,
      name: name,
      participants: participants,
    );
    await roomRef.set(room.toJson());
    return room;
  }

  @override
  Future<void> renameRoom({
    required String dmId,
    required String roomId,
    required String name,
  }) async {
    await _directMessages.doc(dmId).collection('rooms').doc(roomId).update({'name': name});
  }

  @override
  Future<void> setRoomsEnabled(String dmId) async {
    await _directMessages.doc(dmId).update({'roomsEnabled': true});
  }

  @override
  Future<void> deleteRoom({
    required String dmId,
    required String roomId,
    required String requestedBy,
  }) async {
    // watchRoomsと同じ理由でorderBy('createdAt')は使わない。where句は
    // ソートではなくfirestore.rulesの`list`要求を満たすために必須
    // （このwhere句が無いと、rooms=0のpermission-deniedによりこのメソッド
    // 全体が最初のget()で例外を投げ、寄合が削除されないまま残り続けて
    // いた不具合の原因、2026-07-29発覚・修正）。
    final roomsSnapshot = await _directMessages
        .doc(dmId)
        .collection('rooms')
        .where('participants', arrayContains: requestedBy)
        .get();
    if (roomsSnapshot.docs.length <= 1) {
      throw StateError('最後の1つの寄合は削除できません');
    }

    final roomRef = _dmRoomRef(dmId, roomId);
    // 削除の実行者を記録するマーカーを立てる。これを根拠に、以降の
    // メッセージ物理削除がfirestore.rules上許可される
    // （severance/既読オフと同じ「マーカー→カスケード削除」パターン）。
    await roomRef.update({'deletionRequestedBy': requestedBy});

    final messagesRef = roomRef.collection('messages');
    while (true) {
      final snapshot = await messagesRef.limit(400).get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await roomRef.delete();

    final dmDoc = await _directMessages.doc(dmId).get();
    final defaultRoomId = dmDoc.data()?['defaultRoomId'] as String?;
    if (defaultRoomId == roomId) {
      final remaining = roomsSnapshot.docs.where((d) => d.id != roomId).toList()
        ..sort((a, b) =>
            ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo(
                    (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      if (remaining.isNotEmpty) {
        await _directMessages.doc(dmId).update({'defaultRoomId': remaining.first.id});
      }
    }
  }

  @override
  Stream<List<Message>> watchMessages(String dmId, String roomId) {
    return _dmRoomRef(dmId, roomId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Message.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<List<Message>> getMessagesAround({
    required String dmId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  }) async {
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');
    final targetDoc = await messagesRef.doc(messageId).get();
    final targetData = targetDoc.data();
    if (targetData == null) return [];
    final targetSentAt = targetData['sentAt'] as Timestamp?;
    if (targetSentAt == null) return [];

    final olderAndTarget = await messagesRef
        .orderBy('sentAt', descending: true)
        .where('sentAt', isLessThanOrEqualTo: targetSentAt)
        .limit(contextSize)
        .get();
    final newer = await messagesRef
        .orderBy('sentAt')
        .where('sentAt', isGreaterThan: targetSentAt)
        .limit(contextSize)
        .get();

    return [
      for (final doc in olderAndTarget.docs)
        Message.fromJson(doc.id, doc.data()),
      for (final doc in newer.docs) Message.fromJson(doc.id, doc.data()),
    ];
  }

  @override
  Future<void> sendTextMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
    Message? replyTo,
  }) async {
    final roomRef = _dmRoomRef(dmId, roomId);
    final messageRef = roomRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
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
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    // 語らい一覧（TalksTab）はDM単位でlastMessageAt順に並ぶため、寄合側に
    // 加えてDM本体のlastMessageAtも更新する（どの寄合に投稿しても一覧の
    // 並び順に反映されるようにするため）。
    batch.update(_directMessages.doc(dmId), {
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
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
    final dmDoc = await dmRef.get();
    final defaultRoomId = dmDoc.data()?['defaultRoomId'] as String?;
    if (defaultRoomId == null) return;
    final roomRef = dmRef.collection('rooms').doc(defaultRoomId);
    final messageRef = roomRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: defaultRoomId,
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
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    batch.update(dmRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> editMessage({
    required String dmId,
    required String roomId,
    required String messageId,
    required String newContent,
  }) async {
    await _dmRoomRef(dmId, roomId).collection('messages').doc(messageId).update({
      'content': newContent,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unsendMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');
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
    required String roomId,
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    final ref = _dmRoomRef(dmId, roomId).collection('messages').doc(messageId);
    await ref.update({
      'reactions.$userId': emoji ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> markMessagesRead({
    required String dmId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');
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
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final dmSnapshot = await _directMessages.doc(dmId).get();
    final participants = List<String>.from(
      dmSnapshot.data()?['participants'] as List? ?? const [],
    );
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');

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
    // where句はfirestore.rulesの`list`要求を満たすために必須
    // （`deleteRoom`と同じ、2026-07-29追加）。
    final roomsSnapshot = await dmRef
        .collection('rooms')
        .where('participants', arrayContains: currentUserId)
        .get();

    // Firestoreの1バッチは500件までのため、無くなるまでページ単位で削除を
    // 繰り返す（全寄合分）。DMドキュメント自体（severanceRequestedByフラグ）
    // はこの間消さずに残しておく必要がある（各messageのdeleteルールが
    // このフラグを参照して双方合意済みかどうかを検証するため）。
    for (final roomDoc in roomsSnapshot.docs) {
      final messagesRef = roomDoc.reference.collection('messages');
      while (true) {
        final snapshot = await messagesRef.limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await roomDoc.reference.delete();
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
      // where句はfirestore.rulesの`list`要求を満たすために必須
      // （`deleteRoom`と同じ、2026-07-29追加）。
      final roomsSnapshot = await dmRef
          .collection('rooms')
          .where('participants', arrayContains: currentUserId)
          .get();
      for (final roomDoc in roomsSnapshot.docs) {
        await _clearAllReadReceipts(roomDoc.reference.collection('messages'));
      }
    }
  }

  @override
  Future<void> declineAccountDeletionNotice({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    await _dmRoomRef(dmId, roomId)
        .collection('messages')
        .doc(messageId)
        .update({'accountDeletionResponse': 'declined'});
  }

  @override
  Future<void> deleteDmAfterAccountDeletion(String dmId, {required String userId}) async {
    final dmRef = _directMessages.doc(dmId);
    final roomsSnapshot = await dmRef
        .collection('rooms')
        .where('participants', arrayContains: userId)
        .get();

    // acceptSeveranceと同じページ単位の削除ループ（削除済みのdocは次回
    // 取得に現れないため.limit(400)の繰り返し取得で全件処理できる）。
    // friends/friendRequestsのカスケード削除は、アカウント削除処理
    // （Cloud Functions）が既に行っているためここでは不要。
    for (final roomDoc in roomsSnapshot.docs) {
      final messagesRef = roomDoc.reference.collection('messages');
      while (true) {
        final snapshot = await messagesRef.limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await roomDoc.reference.delete();
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
