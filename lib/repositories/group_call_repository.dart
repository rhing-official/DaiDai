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

  /// その広場で現在進行中の通話（あれば1件）を監視する。
  Stream<GroupCall?> watchActiveGroupCall(String groupId);

  Future<GroupCall?> getGroupCall(String groupCallId);

  /// 進行中の通話に参加する（参加者ドキュメントを作成する）。
  Future<void> joinGroupCall({
    required String groupCallId,
    required AppUser user,
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
    bool? cameraOff,
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

  CollectionReference<Map<String, dynamic>> _participantsOf(
    String groupCallId,
  ) =>
      _groupCalls.doc(groupCallId).collection('participants');

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
  Future<GroupCall?> getGroupCall(String groupCallId) async {
    final doc = await _groupCalls.doc(groupCallId).get();
    if (!doc.exists) return null;
    return GroupCall.fromJson(doc.id, doc.data()!);
  }

  @override
  Future<void> joinGroupCall({
    required String groupCallId,
    required AppUser user,
  }) async {
    final participant = CallParticipant(userId: user.userId, rhingId: user.rhingId);
    await _participantsOf(groupCallId)
        .doc(user.userId)
        .set(participant.toJson());
  }

  @override
  Future<void> leaveGroupCall({
    required String groupCallId,
    required String userId,
  }) async {
    await _participantsOf(groupCallId).doc(userId).delete();

    final remaining = await _participantsOf(groupCallId).limit(1).get();
    if (remaining.docs.isEmpty) {
      await _groupCalls.doc(groupCallId).update({
        'status': GroupCallStatus.ended.name,
        'endedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Stream<List<CallParticipant>> watchParticipants(String groupCallId) {
    return _participantsOf(groupCallId).snapshots().map((snapshot) => snapshot
        .docs
        .map((doc) => CallParticipant.fromJson(doc.id, doc.data()))
        .toList());
  }

  @override
  Future<void> touchPresence({
    required String groupCallId,
    required String userId,
  }) async {
    await _participantsOf(groupCallId)
        .doc(userId)
        .update({'lastSeenAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> updateParticipantState({
    required String groupCallId,
    required String userId,
    bool? micMuted,
    bool? cameraOff,
  }) async {
    final data = <String, dynamic>{};
    if (micMuted != null) data['micMuted'] = micMuted;
    if (cameraOff != null) data['cameraOff'] = cameraOff;
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
    await _peerLinksOf(groupCallId)
        .doc(pairId)
        .collection(_candidateCollection(isUserA))
        .add(candidate);
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
