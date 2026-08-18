import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/group.dart';
import '../models/group_call.dart';

/// 広場（グループ）通話のシグナリングを扱うリポジトリ。メッシュ型P2Pのため、
/// 参加者Nに対してN(N-1)/2組のペアそれぞれで独立にoffer/answer/ICE candidateを
/// やり取りする（[CallPeerLink]参照）。1対1の[CallRepository]とは別に持ち、
/// 既存のDM通話には一切影響しない。
abstract class GroupCallRepository {
  /// 広場に新しい通話を開始する。発起人自身の参加者登録は行わないため、
  /// 呼び出し側は続けて[joinGroupCall]（または[WebrtcGroupCallController]の
  /// `initialize()`）を呼ぶこと。
  Future<GroupCall> createGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
  });

  /// 広場に進行中の通話が既にあればそれを返し、無ければ新規作成する。
  ///
  /// 「まず`watchActiveGroupCall`等で確認してから無ければ[createGroupCall]する」
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
  });

  /// その広場で現在進行中の通話（あれば1件）を監視する。
  Stream<GroupCall?> watchActiveGroupCall(String groupId);

  /// 自分がメンバーになっている広場すべてを横断して、現在進行中の通話一覧を
  /// 監視する（着信バナー表示用）。
  Stream<List<GroupCall>> watchActiveGroupCallsForMember(String userId);

  Future<GroupCall?> getGroupCall(String groupCallId);

  /// 進行中の通話に参加する（参加者ドキュメントを作成する）。[isVideo]は
  /// 参加する時点で自分がビデオ通話として参加するかどうか（参加者ごとに
  /// 独立しており、以後[updateParticipantState]で自分だけ切り替えられる）。
  Future<void> joinGroupCall({
    required String groupCallId,
    required AppUser user,
    required bool isVideo,
  });

  /// 通話から退出する。退出後に参加者が0人になった場合は通話自体も終了扱いにする。
  Future<void> leaveGroupCall({
    required String groupCallId,
    required String userId,
  });

  Stream<List<CallParticipant>> watchParticipants(String groupCallId);

  /// 在室確認のハートビート。Firestoreに切断検知の仕組みがないため、
  /// 在室中はクライアントが定期的に呼び続け、他の参加者はこれが一定時間
  /// 途絶えた相手を離脱扱いにする。
  Future<void> touchPresence({
    required String groupCallId,
    required String userId,
  });

  Future<void> updateParticipantState({
    required String groupCallId,
    required String userId,
    bool? micMuted,
    bool? isVideo,
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

  /// 広場ごとに1件だけ存在する、「現在アクティブな通話id」への軽量な
  /// ポインタ。ドキュメントidをgroupIdそのものにすることで、
  /// トランザクション内でクエリを使わずに単一ドキュメント参照として
  /// 読み書きできるようにしている（Firestoreのトランザクションは
  /// 特定のドキュメント参照の読み取りしか許可されず、クエリは使えないため）。
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
  }) async {
    final ref = _groupCalls.doc();
    final call = GroupCall(
      groupCallId: ref.id,
      groupId: group.groupId,
      initiatorId: initiator.userId,
      memberIds: group.memberIds,
      status: GroupCallStatus.active,
      isVideo: isVideo,
    );

    await ref.set(call.toJson());

    return call;
  }

  @override
  Future<GroupCall> getOrCreateActiveGroupCall({
    required Group group,
    required AppUser initiator,
    bool isVideo = false,
  }) async {
    final pointerRef = _activeCallPointer(group.groupId);
    return _firestore.runTransaction<GroupCall>((transaction) async {
      final pointerSnap = await transaction.get(pointerRef);
      final existingCallId = pointerSnap.data()?['activeCallId'] as String?;
      if (existingCallId != null) {
        final existingCallRef = _groupCalls.doc(existingCallId);
        final existingCallSnap = await transaction.get(existingCallRef);
        final existingData = existingCallSnap.data();
        if (existingCallSnap.exists &&
            existingData != null &&
            existingData['status'] == GroupCallStatus.active.name) {
          return GroupCall.fromJson(existingCallSnap.id, existingData);
        }
      }

      final newCallRef = _groupCalls.doc();
      final call = GroupCall(
        groupCallId: newCallRef.id,
        groupId: group.groupId,
        initiatorId: initiator.userId,
        memberIds: group.memberIds,
        status: GroupCallStatus.active,
        isVideo: isVideo,
      );
      transaction.set(newCallRef, call.toJson());
      transaction.set(pointerRef, {'activeCallId': newCallRef.id});
      return call;
    });
  }

  @override
  Stream<GroupCall?> watchActiveGroupCall(String groupId) {
    return _groupCalls
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: GroupCallStatus.active.name)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          return GroupCall.fromJson(doc.id, doc.data());
        });
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
  }) async {
    final participant = CallParticipant(
      userId: user.userId,
      rhingId: user.rhingId,
      isVideo: isVideo,
    );
    await _participantsOf(
      groupCallId,
    ).doc(user.userId).set(participant.toJson());
  }

  @override
  Future<void> leaveGroupCall({
    required String groupCallId,
    required String userId,
  }) async {
    await _participantsOf(groupCallId).doc(userId).delete();

    final remaining = await _participantsOf(groupCallId).limit(1).get();
    if (remaining.docs.isEmpty) {
      final call = await getGroupCall(groupCallId);
      await _groupCalls.doc(groupCallId).update({
        'status': GroupCallStatus.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
      });
      // 通話終了時、ポインタ（groupActiveCallPointers）がまだこの通話を
      // 指していれば解除する。次に誰かが通話を開始した時、既に終了した
      // この通話を「進行中」として誤って掴んでしまわないようにするため。
      // ポインタが既に別の新しい通話idを指している場合は触らない
      // （その新しい通話に影響を与えないよう、現在指している値を
      // トランザクション内で確認してから解除する）。
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
  Future<void> touchPresence({
    required String groupCallId,
    required String userId,
  }) async {
    await _participantsOf(
      groupCallId,
    ).doc(userId).update({'lastSeenAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> updateParticipantState({
    required String groupCallId,
    required String userId,
    bool? micMuted,
    bool? isVideo,
  }) async {
    final data = <String, dynamic>{};
    if (micMuted != null) data['micMuted'] = micMuted;
    if (isVideo != null) data['isVideo'] = isVideo;
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
