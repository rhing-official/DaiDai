import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/group.dart';
import '../features/call/call_log.dart';
import '../models/group_call.dart';

/// 広場（グループ）通話のシグナリングを扱うリポジトリ。メッシュ型P2Pの為、
/// 参加者Nに対してN(N-1)/2組のペアそれぞれで独立にoffer/answer/ICE candidateを
/// やり取りする（[CallPeerLink]参照）。1対1の[CallRepository]とは別に持ち、
/// 既存のDM通話には一切影響しない。
abstract class GroupCallRepository {
  /// 広場に新しい通話を開始する。発起人自身の参加者登録は行わない為、
  /// 呼び出し側は続けて[joinGroupCall]（又は[WebrtcGroupCallController]の
  /// `initialize()`）を呼ぶこと。
  Future<GroupCall> createGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
    String? roomId,
  });

  /// 広場に進行中の通話が既にあればそれを返し、無ければ新規作成する。
  ///
  /// 「先ず`watchActiveGroupCall`等で確認してから無ければ[createGroupCall]する」
  /// というcheck-then-act方式は、複数のメンバーがほぼ同時に通話開始ボタンを
  /// 押すと、それぞれが「進行中の通話は無い」と判定して別々に
  /// [createGroupCall]してしまい、参加者がバラバラの通話に分かれてしまう
  /// 不具合の原因になっていた（実際にユーザー報告あり）。この
  /// メソッドはFirestoreのトランザクションで
  /// `groupActiveCallPointers/{groupId}`（現在アクティブな通話idだけを
  /// 指す軽量なポインタドキュメント）を読み書きすることで、
  /// 「無ければ作る」を原子的に行う。
  Future<GroupCall> getOrCreateActiveGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
    String? roomId,
  });

  /// その広場で現在進行中の通話（あれば1件）を監視する。
  Stream<GroupCall?> watchActiveGroupCall(String groupId);

  /// 自分がメンバーになっている広場全てを横断して、現在進行中の通話一覧を
  /// 監視する（着信バナー表示用）。
  Stream<List<GroupCall>> watchActiveGroupCallsForMember(String userId);

  Future<GroupCall?> getGroupCall(String groupCallId);

  /// 進行中の通話に参加する（参加者ドキュメントを作成する）。[isVideo]は
  /// 参加する時点で自分がビデオ通話として参加するかどうか（参加者毎に
  /// 独立しており、以後[updateParticipantState]で自分だけ切り替えられる）。
  /// [sessionId]はこの参加（端末）を区別する値（`CallParticipant.sessionId`）。
  Future<void> joinGroupCall({
    required String groupCallId,
    required AppUser user,
    required bool isVideo,
    String? sessionId,
  });

  /// 通話から退出する。退出後に参加者が0人になった場合は通話自体も終了扱いにする。
  /// [sessionId]を渡した時は、参加者ドキュメントの`sessionId`が一致する（又は
  /// 無い）時だけ削除する（別の端末が同じ通話に入り直した後に、元の端末の退出が
  /// 新しい端末の参加を消さないようにする、2026-10-21）。
  Future<void> leaveGroupCall({
    required String groupCallId,
    required String userId,
    String? sessionId,
  });

  /// 誰も生きて残っていない通話（[isGroupCallAbandoned]）を終了扱いにする
  /// （冪等）。退出処理が走らずに`active`のまま残った通話の後始末。
  Future<void> endGroupCallIfAbandoned(String groupCallId);

  Stream<List<CallParticipant>> watchParticipants(String groupCallId);

  /// 在室確認のハートビート。Firestoreに切断検知の仕組みが無い為、
  /// 在室中はクライアントが定期的に呼び続け、他の参加者はこれが一定時間
  /// 途絶えた相手を離脱扱いにする。
  ///
  /// [sessionId]を渡した時は、参加者ドキュメントの`sessionId`が別の端末のもの
  /// なら何もしない（別の端末が入り直した後も、元の端末が新しい端末の在室を
  /// 更新し続けてしまわないように、2026-10-31）。別の端末のものだった時は`false`を返す
  /// （自分の参加のままなら`true`。呼び出し側は、`false`なら乗っ取られたとして通話を抜ける、2026-11-16）。
  Future<bool> touchPresence({
    required String groupCallId,
    required String userId,
    String? sessionId,
  });

  Future<void> updateParticipantState({
    required String groupCallId,
    required String userId,
    bool? micMuted,
    bool? micUnavailable,
    bool? isVideo,

    /// 流しているBGMの曲名・一時停止か・小さなジャケット（base64）。[clearBgm]がtrueなら消す（流していない状態）。
    String? bgmTitle,
    bool? bgmPaused,
    String? bgmCover,
    bool clearBgm = false,

    /// 画面共有中の画質の表示。[clearScreen]がtrueなら消す（共有していない状態）。
    String? screenLabel,
    bool clearScreen = false,

    /// 画面が届かなかった配信者の追加・解除（自分の参加者ドキュメントの`screenFailedFor`）。
    String? screenFailedAdd,
    String? screenFailedRemove,
  });

  /// 2人ぶんのペアリンクを作成する（offer/answerのやり取りを始める前に、
  /// ICE candidateサブコレクションの親ドキュメントとして先に存在させておく）。
  Future<void> initiatePeerLink({
    required String groupCallId,
    required String userAId,
    required String userBId,
  });

  Future<void> setPeerOffer({
    required String groupCallId,
    required String pairId,
    required Map<String, dynamic> offer,
  });

  Future<void> setPeerAnswer({
    required String groupCallId,
    required String pairId,
    required Map<String, dynamic> answer,
  });

  Stream<CallPeerLink?> watchPeerLink({
    required String groupCallId,
    required String pairId,
  });

  /// [isUserA]は「自分がこのペアのuserAか」を示す。ICE candidateは自分の側の
  /// サブコレクション（userAなら`candidatesA`）に書き込む。
  Future<void> addPeerCandidate({
    required String groupCallId,
    required String pairId,
    required bool isUserA,
    required Map<String, dynamic> candidate,
  });

  /// 相手側のサブコレクションを購読する（自分がuserAなら`candidatesB`を見る）。
  Stream<List<Map<String, dynamic>>> watchPeerCandidates({
    required String groupCallId,
    required String pairId,
    required bool isUserA,
  });
}

class FirestoreGroupCallRepository implements GroupCallRepository {
  FirestoreGroupCallRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _groupCalls =>
      _firestore.collection('groupCalls');

  /// 広場毎に1件だけ存在する、「現在アクティブな通話id」への軽量な
  /// ポインタ。ドキュメントidをgroupIdそのものにすることで、
  /// トランザクション内でクエリを使わずに単一ドキュメント参照として
  /// 読み書き出来るようにしている（Firestoreのトランザクションは
  /// 特定のドキュメント参照の読み取りしか許可されず、クエリは使えない為）。
  DocumentReference<Map<String, dynamic>> _activeCallPointer(String groupId) =>
      _firestore.collection('groupActiveCallPointers').doc(groupId);

  CollectionReference<Map<String, dynamic>> _participantsOf(
    String groupCallId,
  ) => _groupCalls.doc(groupCallId).collection('participants');

  CollectionReference<Map<String, dynamic>> _peerLinksOf(String groupCallId) =>
      _groupCalls.doc(groupCallId).collection('peerLinks');

  String _candidateCollection(bool isUserA) =>
      isUserA ? 'candidatesA' : 'candidatesB';

  @override
  Future<GroupCall> createGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
    String? roomId,
  }) async {
    final ref = _groupCalls.doc();
    final call = GroupCall(
      groupCallId: ref.id,
      groupId: group.groupId,
      initiatorId: initiator.userId,
      memberIds: group.memberIds,
      status: GroupCallStatus.active,
      isVideo: isVideo,
      roomId: roomId,
    );

    await ref.set(call.toJson());

    return call;
  }

  @override
  Future<GroupCall> getOrCreateActiveGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
    String? roomId,
  }) async {
    final pointerRef = _activeCallPointer(group.groupId);
    return _firestore.runTransaction<GroupCall>((transaction) async {
      final pointerSnap = await transaction.get(pointerRef);
      final existingCallId = pointerSnap.data()?['activeCallId'] as String?;
      var reason = 'pointer=none';
      if (existingCallId != null) {
        final existingCallRef = _groupCalls.doc(existingCallId);
        final existingCallSnap = await transaction.get(existingCallRef);
        final existingData = existingCallSnap.data();
        if (existingCallSnap.exists &&
            existingData != null &&
            existingData['status'] == GroupCallStatus.active.name) {
          callLog('group call: reuse $existingCallId (group=${group.groupId})');
          return GroupCall.fromJson(existingCallSnap.id, existingData);
        }
        reason =
            'pointer=$existingCallId exists=${existingCallSnap.exists} '
            'status=${existingData?['status']}';
      }
      callLog('group call: create new (group=${group.groupId}) $reason');

      final newCallRef = _groupCalls.doc();
      final call = GroupCall(
        groupCallId: newCallRef.id,
        groupId: group.groupId,
        initiatorId: initiator.userId,
        memberIds: group.memberIds,
        status: GroupCallStatus.active,
        isVideo: isVideo,
        roomId: roomId,
      );
      transaction.set(newCallRef, call.toJson());
      transaction.set(pointerRef, {'activeCallId': newCallRef.id});
      return call;
    });
  }

  /// ポインタ（`groupActiveCallPointers/{groupId}`）→通話の単一ドキュメント、の順に購読する
  /// （2026-11-16）。以前は`groupCalls`を`groupId`・`status`だけで絞って購読しており、ルール
  /// （`uid in resource.data.memberIds`）をクエリが証明できず`permission-denied`で拒否され、
  /// キャッシュの最初の1回だけ返って以後は更新されなかった（読み込み後に始まった通話のバナーが、
  /// 再読み込みするまで出ない不具合）。単一ドキュメントの購読ならルールを満たし、インデックスも要らない。
  @override
  Stream<GroupCall?> watchActiveGroupCall(String groupId) {
    late final StreamController<GroupCall?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? pointerSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? callSub;
    controller = StreamController<GroupCall?>(
      onListen: () {
        pointerSub = _activeCallPointer(groupId).snapshots().listen((pointer) {
          final id = pointer.data()?['activeCallId'] as String?;
          callSub?.cancel();
          callSub = null;
          if (id == null) {
            controller.add(null);
            return;
          }
          callSub = _groupCalls
              .doc(id)
              .snapshots()
              .listen(
                (doc) =>
                    controller.add(activeGroupCallFromData(doc.id, doc.data())),
                onError: controller.addError,
              );
        }, onError: controller.addError);
      },
      onCancel: () async {
        await callSub?.cancel();
        await pointerSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<GroupCall>> watchActiveGroupCallsForMember(String userId) {
    return _groupCalls
        .where('memberIds', arrayContains: userId)
        .where('status', isEqualTo: GroupCallStatus.active.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupCall.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<GroupCall?> getGroupCall(String groupCallId) async {
    final doc = await _groupCalls.doc(groupCallId).get();
    if (!doc.exists) return null;
    return GroupCall.fromJson(doc.id, doc.data()!);
  }

  @override
  Future<void> joinGroupCall({
    required String groupCallId,
    required AppUser user,
    required bool isVideo,
    String? sessionId,
  }) async {
    callLog('group call: join $groupCallId (user=${user.userId})');
    final participant = CallParticipant(
      userId: user.userId,
      rhingSeed: user.rhingSeed,
      isVideo: isVideo,
      sessionId: sessionId,
    );
    await _participantsOf(
      groupCallId,
    ).doc(user.userId).set(participant.toJson());
    // 誰かが入ったことを残す（参加者の記録は抜けると消えるため）。通話の記録
    // （Cloud Functions）が、始めた人以外が入らなかった通話を不在着信と判断する（2026-11-17）。
    await _groupCalls.doc(groupCallId).update({
      'joinedUserIds': FieldValue.arrayUnion([user.userId]),
    });
  }

  @override
  Future<void> leaveGroupCall({
    required String groupCallId,
    required String userId,
    String? sessionId,
  }) async {
    final participantRef = _participantsOf(groupCallId).doc(userId);
    if (sessionId != null) {
      final current = (await participantRef.get()).data()?['sessionId'];
      // 別の端末が入り直した後なら、その参加を消さず、通話も終わらせない。
      if (current is String && current != sessionId) return;
    }
    await participantRef.delete();

    // 残っているのがハートビート切れの残骸だけなら、通話も終了扱いにする。
    final remaining = await _participantsOf(groupCallId).get();
    final live = liveParticipantCount(
      remaining.docs
          .map((doc) => CallParticipant.fromJson(doc.id, doc.data()))
          .toList(),
      DateTime.now(),
    );
    if (live == 0) await _endCall(groupCallId);
  }

  @override
  Future<void> endGroupCallIfAbandoned(String groupCallId) async {
    final call = await getGroupCall(groupCallId);
    if (call == null || call.status != GroupCallStatus.active) return;
    final snapshot = await _participantsOf(groupCallId).get();
    final participants = snapshot.docs
        .map((doc) => CallParticipant.fromJson(doc.id, doc.data()))
        .toList();
    if (!isGroupCallAbandoned(
      participants: participants,
      createdAt: call.createdAt,
      now: DateTime.now(),
    )) {
      return;
    }
    callLog(
      'group call: ending abandoned $groupCallId '
      'participants=${participants.length}',
    );
    await _endCall(groupCallId);
  }

  Future<void> _endCall(String groupCallId) async {
    final call = await getGroupCall(groupCallId);
    await _groupCalls.doc(groupCallId).update({
      'status': GroupCallStatus.ended.name,
      'endedAt': FieldValue.serverTimestamp(),
    });
    // 通話終了時、ポインタ（groupActiveCallPointers）がまだこの通話を
    // 指していれば解除する。次に誰かが通話を開始した時、既に終了した
    // この通話を「進行中」として誤って掴んでしまわないようにする為。
    // ポインタが既に別の新しい通話idを指している場合は触らない
    // （トランザクション内で現在指している値を確認してから解除する）。
    if (call != null) {
      final pointerRef = _activeCallPointer(call.groupId);
      await _firestore.runTransaction((transaction) async {
        final pointerSnap = await transaction.get(pointerRef);
        if (pointerSnap.data()?['activeCallId'] == groupCallId) {
          transaction.update(pointerRef, {'activeCallId': null});
        }
      });
    }
  }

  @override
  Stream<List<CallParticipant>> watchParticipants(String groupCallId) {
    return _participantsOf(groupCallId).snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => CallParticipant.fromJson(doc.id, doc.data()))
          .toList(),
    );
  }

  @override
  Future<bool> touchPresence({
    required String groupCallId,
    required String userId,
    String? sessionId,
  }) async {
    final ref = _participantsOf(groupCallId).doc(userId);
    if (sessionId != null) {
      final current = (await ref.get()).data()?['sessionId'];
      if (current is String && current != sessionId) return false;
    }
    await ref.update({'lastSeenAt': FieldValue.serverTimestamp()});
    return true;
  }

  @override
  Future<void> updateParticipantState({
    required String groupCallId,
    required String userId,
    bool? micMuted,
    bool? micUnavailable,
    bool? isVideo,
    String? bgmTitle,
    bool? bgmPaused,
    String? bgmCover,
    bool clearBgm = false,
    String? screenLabel,
    bool clearScreen = false,
    String? screenFailedAdd,
    String? screenFailedRemove,
  }) async {
    final data = <String, dynamic>{};
    if (micMuted != null) data['micMuted'] = micMuted;
    if (micUnavailable != null) data['micUnavailable'] = micUnavailable;
    if (isVideo != null) data['isVideo'] = isVideo;
    if (bgmTitle != null) {
      data['bgmTitle'] = bgmTitle;
      data['bgmPaused'] = bgmPaused ?? false;
      data['bgmCover'] = bgmCover ?? FieldValue.delete();
    }
    if (clearBgm) {
      data['bgmTitle'] = FieldValue.delete();
      data['bgmPaused'] = FieldValue.delete();
      data['bgmCover'] = FieldValue.delete();
    }
    if (screenLabel != null) data['screenLabel'] = screenLabel;
    if (clearScreen) data['screenLabel'] = FieldValue.delete();
    if (screenFailedAdd != null) {
      data['screenFailedFor'] = FieldValue.arrayUnion([screenFailedAdd]);
    }
    if (screenFailedRemove != null) {
      data['screenFailedFor'] = FieldValue.arrayRemove([screenFailedRemove]);
    }
    if (data.isEmpty) return;
    await _participantsOf(groupCallId).doc(userId).update(data);
  }

  @override
  Future<void> initiatePeerLink({
    required String groupCallId,
    required String userAId,
    required String userBId,
  }) async {
    final pairId = CallPeerLink.idFor(userAId, userBId);
    final sorted = [userAId, userBId]..sort();
    await _peerLinksOf(groupCallId).doc(pairId).set({
      'userAId': sorted[0],
      'userBId': sorted[1],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setPeerOffer({
    required String groupCallId,
    required String pairId,
    required Map<String, dynamic> offer,
  }) async {
    await _peerLinksOf(groupCallId).doc(pairId).update({
      'offer': offer,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setPeerAnswer({
    required String groupCallId,
    required String pairId,
    required Map<String, dynamic> answer,
  }) async {
    await _peerLinksOf(groupCallId).doc(pairId).update({
      'answer': answer,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<CallPeerLink?> watchPeerLink({
    required String groupCallId,
    required String pairId,
  }) {
    return _peerLinksOf(groupCallId).doc(pairId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CallPeerLink.fromJson(doc.id, doc.data()!);
    });
  }

  @override
  Future<void> addPeerCandidate({
    required String groupCallId,
    required String pairId,
    required bool isUserA,
    required Map<String, dynamic> candidate,
  }) async {
    await _peerLinksOf(
      groupCallId,
    ).doc(pairId).collection(_candidateCollection(isUserA)).add(candidate);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPeerCandidates({
    required String groupCallId,
    required String pairId,
    required bool isUserA,
  }) {
    // 自分がuserAなら相手（userB）側のcandidatesBを、userBならcandidatesAを見る。
    final collection = _candidateCollection(!isUserA);
    return _peerLinksOf(groupCallId)
        .doc(pairId)
        .collection(collection)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
