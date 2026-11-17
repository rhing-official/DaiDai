import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/call.dart';

abstract class CallRepository {
  /// 一対の相手に通話を発信する（呼び出し中の通話ドキュメントを作成する）。
  /// [isVideo]がtrueならビデオ通話、falseなら音声のみの通話になる。
  Future<Call> createCall({
    required AppUser caller,
    required AppUser callee,
    required String dmId,
    bool isVideo = false,
  });

  Stream<Call?> watchCall(String callId);

  /// 自分宛にかかってきている、応答待ちの通話（あれば1件）を監視する。
  Stream<Call?> watchIncomingCall(String userId);

  /// 自分が発信側・着信側のどちらかで、今つながっている（`active`）通話の一覧
  /// （2026-11-17。別の端末で参加中の一対の通話を、語らい一覧の標に出すため）。
  Stream<List<Call>> watchMyActiveCalls(String userId);

  Future<void> setOffer(String callId, Map<String, dynamic> offer);
  Future<void> setAnswer(String callId, Map<String, dynamic> answer);
  Future<void> updateStatus(String callId, CallStatus status);

  /// 応答する端末を1台に決める。まだ誰も応答していなければ[sessionId]を記録してtrue、
  /// 既に別の端末が応答していればfalseを返す（同時応答の競合を避ける）。
  Future<bool> claimAnswer(String callId, String sessionId);

  /// 通話中に音声⇔ビデオを切り替えた際、種別をFirestore側にも反映する
  /// （画面を離れて戻ってきた場合等に現在の種別を復元出来るようにする為）。
  /// 切り替えるのは自分側の種別のみで、相手側には影響しない
  /// （[isCaller]に応じて`callerIsVideo`/`calleeIsVideo`のどちらかだけ更新する）。
  Future<void> updateIsVideo(
    String callId, {
    required bool isCaller,
    required bool isVideo,
  });

  Future<void> addCandidate({
    required String callId,
    required bool isCaller,
    required Map<String, dynamic> candidate,
  });

  Stream<List<Map<String, dynamic>>> watchCandidates({
    required String callId,
    required bool isCaller,
  });
}

class FirestoreCallRepository implements CallRepository {
  FirestoreCallRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  // 発信者側のICE candidateは`callerCandidates`、着信者側は`calleeCandidates`に
  // それぞれ書き込む（お互いが相手側のサブコレクションを購読する）。
  String _candidateCollection(bool isCaller) =>
      isCaller ? 'callerCandidates' : 'calleeCandidates';

  @override
  Future<Call> createCall({
    required AppUser caller,
    required AppUser callee,
    required String dmId,
    bool isVideo = false,
  }) async {
    final ref = _calls.doc();
    final call = Call(
      callId: ref.id,
      dmId: dmId,
      callerId: caller.userId,
      callerRhingSeed: caller.rhingSeed,
      calleeId: callee.userId,
      calleeRhingSeed: callee.rhingSeed,
      status: CallStatus.ringing,
      isVideo: isVideo,
      callerIsVideo: isVideo,
      calleeIsVideo: isVideo,
    );
    await ref.set(call.toJson());
    return call;
  }

  @override
  Stream<Call?> watchCall(String callId) {
    return _calls.doc(callId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Call.fromJson(doc.id, doc.data()!);
    });
  }

  @override
  Stream<Call?> watchIncomingCall(String userId) {
    return _calls
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          return Call.fromJson(doc.id, doc.data());
        });
  }

  @override
  Stream<List<Call>> watchMyActiveCalls(String userId) {
    late final StreamController<List<Call>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? callerSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? calleeSub;
    var asCaller = <Call>[];
    var asCallee = <Call>[];
    void emit() => controller.add([...asCaller, ...asCallee]);
    List<Call> parse(QuerySnapshot<Map<String, dynamic>> snapshot) =>
        snapshot.docs.map((doc) => Call.fromJson(doc.id, doc.data())).toList();
    controller = StreamController<List<Call>>(
      onListen: () {
        callerSub = _calls
            .where('callerId', isEqualTo: userId)
            .where('status', isEqualTo: CallStatus.active.name)
            .snapshots()
            .listen((snapshot) {
              asCaller = parse(snapshot);
              emit();
            }, onError: controller.addError);
        calleeSub = _calls
            .where('calleeId', isEqualTo: userId)
            .where('status', isEqualTo: CallStatus.active.name)
            .snapshots()
            .listen((snapshot) {
              asCallee = parse(snapshot);
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await callerSub?.cancel();
        await calleeSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setOffer(String callId, Map<String, dynamic> offer) {
    return _calls.doc(callId).update({'offer': offer});
  }

  @override
  Future<void> setAnswer(String callId, Map<String, dynamic> answer) {
    return _calls.doc(callId).update({
      'answer': answer,
      'status': CallStatus.active.name,
      // 応答時刻。通話の記録（Cloud Functions）の通話時間に使う（2026-11-17）。
      'connectedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateIsVideo(
    String callId, {
    required bool isCaller,
    required bool isVideo,
  }) {
    final field = isCaller ? 'callerIsVideo' : 'calleeIsVideo';
    return _calls.doc(callId).update({field: isVideo});
  }

  @override
  Future<bool> claimAnswer(String callId, String sessionId) {
    final ref = _calls.doc(callId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = snap.data()?['answeredBy'] as String?;
      if (current != null && current != sessionId) return false;
      tx.update(ref, {'answeredBy': sessionId});
      return true;
    });
  }

  @override
  Future<void> updateStatus(String callId, CallStatus status) {
    final data = <String, dynamic>{'status': status.name};
    if (status == CallStatus.ended ||
        status == CallStatus.declined ||
        status == CallStatus.missed) {
      data['endedAt'] = FieldValue.serverTimestamp();
    }
    return _calls.doc(callId).update(data);
  }

  @override
  Future<void> addCandidate({
    required String callId,
    required bool isCaller,
    required Map<String, dynamic> candidate,
  }) {
    return _calls
        .doc(callId)
        .collection(_candidateCollection(isCaller))
        .add(candidate);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchCandidates({
    required String callId,
    required bool isCaller,
  }) {
    // 自分が発信者ならcalleeCandidates（相手側）を、着信者ならcallerCandidatesを購読する。
    final collection = _candidateCollection(!isCaller);
    return _calls
        .doc(callId)
        .collection(collection)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
