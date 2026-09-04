import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show ValueChanged;

import '../models/app_user.dart';
import '../models/day_messages_page.dart';
import '../models/direct_message.dart';
import '../models/dm_room.dart';
import '../models/message.dart';
import '../utils/attachment_upload.dart';

abstract class DirectMessageRepository {
  /// 2人のuserから一対を取得する。無ければ作成する
  /// （既定の寄合「メイン」も同時に1件作る）。
  Future<DirectMessage> getOrCreateDirectMessage(AppUser a, AppUser b);

  /// dmId単体からDirectMessageを取得する（プッシュ通知タップでの
  /// ディープリンク等、IDしか持たない場面向け。参加者でない/存在しない場合
  /// はnull、2026-09-02追加）。
  Future<DirectMessage?> getDirectMessage(String dmId);

  /// 自分が参加している一対一覧を、最終メッセージが新しい順に取得する。
  Stream<List<DirectMessage>> watchDirectMessages(String userId);

  /// この一対の寄合（テキストチャンネル）一覧を作成順に購読する。[userId]は
  /// 呼び出し元本人のuserId（firestore.rulesの`list`操作はクエリ自体に
  /// ルールと同じ条件の`where`句が無いと要求全体を拒否するため、クエリ側にも
  /// `participants`のarray-contains条件を付ける必要がある。
  /// `GroupRepository.watchRooms`参照）。
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  });

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

  /// 直近に活動があった暦日（メッセージが送信されたローカル日付）1日分の
  /// メッセージをライブ購読する（2026-08-20追加、1日単位ページネーションの
  /// 起点）。日をまたいで新着メッセージが届いても継続して拾われる。
  /// メッセージが1件も無い会話では空リストのまま。
  Stream<DayMessagesPage> watchLatestDayMessages(String dmId, String roomId);

  /// [beforeDayStart]（暦日の開始時刻）より古い、直近の「メッセージが
  /// 存在する暦日」1日分を1回だけ取得する（2026-08-20追加）。該当する
  /// メッセージが無ければ（＝これ以上遡る履歴が無ければ）nullを返す。
  /// [watchLatestDayMessages]と異なりライブ購読はしない（過去日は静的な
  /// スナップショットのまま、既読・編集・削除等はその日を開き直すまで
  /// 反映されない）。
  Future<DayMessagesPage?> loadOlderDayMessages({
    required String dmId,
    required String roomId,
    required DateTime beforeDayStart,
  });

  /// [watchMessages]の直近50件に含まれない古い返信先へジャンプする際に使う。
  /// 指定した[messageId]を含む前後合わせて最大[contextSize]*2件を1回だけ
  /// 取得する（購読はしない）。対象メッセージが既に削除済みの場合は空を返す。
  Future<List<Message>> getMessagesAround({
    required String dmId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  });

  /// 指定した1件のメッセージの最新状態を1回だけ取得する（2026-08-21追加）。
  /// [loadOlderDayMessages]で読み込んだ過去日はライブ購読しない静的な
  /// スナップショットのため、その中のメッセージへ編集・リアクション等を
  /// 行った直後にローカル側の表示を更新する目的で使う。既に物理削除済み
  /// （送信取り消し等）ならnullを返す。
  Future<Message?> getMessage({
    required String dmId,
    required String roomId,
    required String messageId,
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

  /// ファイル・画像・動画を添付したメッセージを送信する（技術仕様書5.2参照、
  /// 2026-08-10追加）。[contentType]はfile|image|videoのいずれか。
  /// 拡張子ブロックリスト・容量上限（[kMaxAttachmentSizeBytes]）はUI側でも
  /// 事前に弾くが、`uploadMessageAttachment`側でも再検証する。画像は
  /// WebPへの圧縮を試みる（失敗時は元のまま）。
  Future<void> sendAttachmentMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    bool silent = false,
    Message? replyTo,
    ValueChanged<double>? onProgress,
  });

  /// ペタピタ（スタンプ）を送る。既にStorageにアップロード済みの画像を
  /// 参照するだけなので、[sendAttachmentMessage]と異なりバイトデータの
  /// アップロードを伴わない（技術仕様書7.4参照、2026-08-11追加）。
  Future<void> sendStickerMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String stickerId,
    required String stickerName,
    required String stickerUrl,
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

  /// カレンダーの予定を追加した際、その寄合に通知メッセージを送る
  /// （2026-09-04追加）。タップすると`showCalendarEventDetailDialog`で
  /// 出欠確認ポップアップを開けるよう[eventId]を持たせる。
  Future<void> sendCalendarEventCreatedMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String eventId,
    required String eventTitle,
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

  /// 自分のこのメッセージへのリアクションを、呼び出し側が計算済みの
  /// 完全な絵文字リストで上書きする（空リストなら解除。2026-08-05変更、
  /// 以前は単一絵文字の設定/解除だったが、複数の異なる絵文字を同時に
  /// 持てるようになったため、差分ではなく完全なリストを渡す形にした）。
  Future<void> setReaction({
    required String dmId,
    required String roomId,
    required String messageId,
    required String userId,
    required List<String> emojis,
  });

  /// メッセージをピン留めする（参加者ならどちらでも実行可能）。
  Future<void> pinMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  });

  /// メッセージのピン留めを解除する（参加者ならどちらでも実行可能）。
  Future<void> unpinMessage({
    required String dmId,
    required String roomId,
    required String messageId,
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
  Future<void> deleteDmAfterAccountDeletion(
    String dmId, {
    required String userId,
  });
}

class FirestoreDirectMessageRepository implements DirectMessageRepository {
  FirestoreDirectMessageRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

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
      return DirectMessage.fromJson(dmId, {
        ...data,
        'defaultRoomId': repairedRoomRef.id,
      });
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
  Future<DirectMessage?> getDirectMessage(String dmId) async {
    try {
      final doc = await _directMessages.doc(dmId).get();
      if (!doc.exists) return null;
      return DirectMessage.fromJson(doc.id, doc.data()!);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
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
          dms.sort(
            (a, b) => (b.lastMessageAt?.millisecondsSinceEpoch ?? 0).compareTo(
              a.lastMessageAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
          return dms;
        });
  }

  @override
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  }) {
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
              snapshot.docs
                  .map((doc) => DmRoom.fromJson(doc.id, doc.data()))
                  .toList()
                ..sort(
                  (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0)
                      .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0),
                );
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
    await _directMessages.doc(dmId).collection('rooms').doc(roomId).update({
      'name': name,
    });
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
        ..sort(
          (a, b) =>
              ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                      0)
                  .compareTo(
                    (b.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0,
                  ),
        );
      if (remaining.isNotEmpty) {
        await _directMessages.doc(dmId).update({
          'defaultRoomId': remaining.first.id,
        });
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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Message.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<DayMessagesPage> watchLatestDayMessages(
    String dmId,
    String roomId,
  ) async* {
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');
    final latest = await messagesRef
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isEmpty) {
      final now = DateTime.now();
      yield DayMessagesPage(
        dayStart: DateTime(now.year, now.month, now.day),
        messages: const [],
      );
      return;
    }
    final sentAt = (latest.docs.first.data()['sentAt'] as Timestamp).toDate();
    final dayStart = DateTime(sentAt.year, sentAt.month, sentAt.day);
    yield* messagesRef
        .where('sentAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => DayMessagesPage(
            dayStart: dayStart,
            messages: snapshot.docs
                .map((doc) => Message.fromJson(doc.id, doc.data()))
                .toList(),
          ),
        );
  }

  @override
  Future<DayMessagesPage?> loadOlderDayMessages({
    required String dmId,
    required String roomId,
    required DateTime beforeDayStart,
  }) async {
    final messagesRef = _dmRoomRef(dmId, roomId).collection('messages');
    final peek = await messagesRef
        .where('sentAt', isLessThan: Timestamp.fromDate(beforeDayStart))
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (peek.docs.isEmpty) return null;
    final sentAt = (peek.docs.first.data()['sentAt'] as Timestamp).toDate();
    final dayStart = DateTime(sentAt.year, sentAt.month, sentAt.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final snapshot = await messagesRef
        .where('sentAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('sentAt', isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy('sentAt', descending: true)
        .get();
    return DayMessagesPage(
      dayStart: dayStart,
      messages: snapshot.docs
          .map((doc) => Message.fromJson(doc.id, doc.data()))
          .toList(),
    );
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
  Future<Message?> getMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    final doc = await _dmRoomRef(
      dmId,
      roomId,
    ).collection('messages').doc(messageId).get();
    final data = doc.data();
    if (data == null) return null;
    return Message.fromJson(doc.id, data);
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
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    // 語らい一覧（TalksTab）はDM単位でlastMessageAt順に並ぶため、寄合側に
    // 加えてDM本体のlastMessageAtも更新する（どの寄合に投稿しても一覧の
    // 並び順に反映されるようにするため）。lastMessageSenderIdは一覧の
    // 「未読優先」並べ替え用（2026-09-02追加）。lastMessageContentType/
    // lastMessagePreviewは一覧の最新メッセージプレビュー表示用
    // （2026-09-02追加）。
    batch.update(_directMessages.doc(dmId), {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageContentType': 'text',
      'lastMessagePreview': messageSnippetOf(content),
    });
    await batch.commit();
  }

  @override
  Future<void> sendAttachmentMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    bool silent = false,
    Message? replyTo,
    ValueChanged<double>? onProgress,
  }) async {
    final roomRef = _dmRoomRef(dmId, roomId);
    final messageRef = roomRef.collection('messages').doc();

    final fileMetadata = await uploadMessageAttachment(
      storage: _storage,
      storagePathPrefix: 'dmFiles/$dmId',
      attachmentId: messageRef.id,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      onProgress: onProgress,
    );

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
      conversationType: 'dm',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: fileName,
      contentType: contentType,
      silent: silent,
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
      fileMetadata: fileMetadata,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    batch.update(_directMessages.doc(dmId), {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageContentType': contentType,
      'lastMessagePreview': null,
    });
    await batch.commit();
  }

  @override
  Future<void> sendStickerMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String stickerId,
    required String stickerName,
    required String stickerUrl,
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
      content: stickerName,
      contentType: 'sticker',
      silent: silent,
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
      stickerData: MessageStickerData(
        stickerId: stickerId,
        stickerUrl: stickerUrl,
      ),
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    batch.update(_directMessages.doc(dmId), {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageContentType': 'sticker',
      'lastMessagePreview': null,
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
    batch.update(dmRef, {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageContentType': 'call',
      'lastMessagePreview': messageSnippetOf(message.content),
    });
    await batch.commit();
  }

  @override
  Future<void> sendCalendarEventCreatedMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String eventId,
    required String eventTitle,
  }) async {
    final dmRef = _directMessages.doc(dmId);
    final roomRef = dmRef.collection('rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
      conversationType: 'dm',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: eventTitle,
      contentType: 'calendarEventCreated',
      calendarEventId: eventId,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    batch.update(dmRef, {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
      'lastMessageContentType': 'calendarEventCreated',
      'lastMessagePreview': messageSnippetOf(message.content),
    });
    await batch.commit();
  }

  @override
  Future<void> editMessage({
    required String dmId,
    required String roomId,
    required String messageId,
    required String newContent,
  }) async {
    await _dmRoomRef(dmId, roomId).collection('messages').doc(messageId).update(
      {'content': newContent, 'editedAt': FieldValue.serverTimestamp()},
    );
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
    // ピン留めされていた場合、寄合側のpinnedMessageIdsからも取り除く
    // （存在しないメッセージへのピン参照が残らないようにする）。
    batch.update(_dmRoomRef(dmId, roomId), {
      'pinnedMessageIds': FieldValue.arrayRemove([messageId]),
    });
    await batch.commit();
  }

  @override
  Future<void> setReaction({
    required String dmId,
    required String roomId,
    required String messageId,
    required String userId,
    required List<String> emojis,
  }) async {
    final ref = _dmRoomRef(dmId, roomId).collection('messages').doc(messageId);
    await ref.update({
      'reactions.$userId': emojis.isEmpty ? FieldValue.delete() : emojis,
    });
  }

  @override
  Future<void> pinMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    await _dmRoomRef(dmId, roomId).update({
      'pinnedMessageIds': FieldValue.arrayUnion([messageId]),
    });
  }

  @override
  Future<void> unpinMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    await _dmRoomRef(dmId, roomId).update({
      'pinnedMessageIds': FieldValue.arrayRemove([messageId]),
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
    final attachmentUrlsToDelete = <String>[];
    for (var i = 0; i < docs.length; i += 400) {
      final chunk = docs.sublist(
        i,
        i + 400 > docs.length ? docs.length : i + 400,
      );
      final batch = _firestore.batch();
      final deletedMessageIds = <String>[];
      for (final doc in chunk) {
        if (!doc.exists) continue;
        final hiddenFor = {
          ...?(doc.data()?['hiddenFor'] as List?)?.cast<String>(),
          userId,
        };
        if (participants.every(hiddenFor.contains)) {
          batch.delete(doc.reference);
          deletedMessageIds.add(doc.id);
          final fileUrl =
              (doc.data()?['fileMetadata'] as Map<String, dynamic>?)?['url']
                  as String?;
          if (fileUrl != null) attachmentUrlsToDelete.add(fileUrl);
        } else {
          batch.update(doc.reference, {
            'hiddenFor': FieldValue.arrayUnion([userId]),
          });
        }
      }
      // 物理削除されたメッセージがピン留めされていた場合、寄合側の
      // pinnedMessageIdsからも取り除く。
      if (deletedMessageIds.isNotEmpty) {
        batch.update(_dmRoomRef(dmId, roomId), {
          'pinnedMessageIds': FieldValue.arrayRemove(deletedMessageIds),
        });
      }
      await batch.commit();
    }

    // 参加者全員が削除し終え物理削除されたメッセージの添付ファイルは、
    // Firestore上には残らないがFirebase Storage上には実体が残るため、
    // ストレージの肥大化防止のためあわせて削除する（削除失敗は無視）。
    await Future.wait(
      attachmentUrlsToDelete.map((url) async {
        try {
          await _storage.refFromURL(url).delete();
        } catch (_) {}
      }),
    );
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

    // 友達関係を実際に終わらせるcascadeBatchを最優先・最初に実行する
    // （2026-09-01変更、以前はメッセージ・寄合の削除ループの後に実行して
    // いた）。firestore.rules上、friends/friendRequestsの削除条件は
    // 「一対ドキュメントにseveranceRequestedByが立っていて削除者が提案者
    // 本人でないこと」のみでメッセージ削除の完了を前提としないため、
    // 順序を入れ替えても問題ない。以前の順序だと、時間のかかるメッセージ
    // 削除ループの途中でタブを閉じる・通信切断等により処理が中断された場合、
    // 会話は消えて絶縁が完了したように見えてもfriendsドキュメントが
    // 削除されないまま残り、後から「すでに友達です」と表示される不具合が
    // あった。友達関係の解消を最優先の原子的操作として先に完了させることで、
    // 以降の処理が中断されても実害の少ない残骸（空のメッセージ・寄合・
    // 一対ドキュメント）が残るだけで済むようにする。
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
    await _dmRoomRef(dmId, roomId).collection('messages').doc(messageId).update(
      {'accountDeletionResponse': 'declined'},
    );
  }

  @override
  Future<void> deleteDmAfterAccountDeletion(
    String dmId, {
    required String userId,
  }) async {
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
