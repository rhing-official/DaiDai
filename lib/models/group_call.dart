import 'package:cloud_firestore/cloud_firestore.dart';

/// 広場（グループ）通話の参加上限。メッシュ型P2Pは人数が増えるほど
/// 各端末の通信量・CPU負荷が急増するため、実用上の目安である4〜5人に
/// 絞っている（2026-07-24、ユーザー確認の上で決定。SFU導入は将来検討）。
const kMaxGroupCallParticipants = 5;

/// グループ通話の状態。1対1の`CallStatus`と異なり、着信（ringing）の概念を
/// 持たない。「進行中の通話に途中から参加する」プル型モデルのため。
enum GroupCallStatus {
  active,
  ended;

  static GroupCallStatus fromName(String name) {
    return GroupCallStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => GroupCallStatus.ended,
    );
  }
}

/// 広場（グループ）通話。メッシュ型P2Pのため参加者同士が直接
/// `RTCPeerConnection`を張り合う（[CallPeerLink]参照）。
class GroupCall {
  const GroupCall({
    required this.groupCallId,
    required this.groupId,
    required this.initiatorId,
    required this.memberIds,
    required this.status,
    this.isVideo = false,
    this.maxParticipants = kMaxGroupCallParticipants,
    this.createdAt,
    this.endedAt,
  });

  final String groupCallId;
  final String groupId;
  final String initiatorId;

  /// 通話開始時点の広場メンバーを非正規化して保持する
  /// （`Room.memberIds`と同じ考え方。Firestoreルールでの参照を単純化する）。
  final List<String> memberIds;

  final GroupCallStatus status;
  final bool isVideo;
  final int maxParticipants;
  final Timestamp? createdAt;
  final Timestamp? endedAt;

  factory GroupCall.fromJson(String groupCallId, Map<String, dynamic> json) {
    return GroupCall(
      groupCallId: groupCallId,
      groupId: json['groupId'] as String,
      initiatorId: json['initiatorId'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      status: GroupCallStatus.fromName(json['status'] as String),
      isVideo: json['isVideo'] as bool? ?? false,
      maxParticipants:
          json['maxParticipants'] as int? ?? kMaxGroupCallParticipants,
      createdAt: json['createdAt'] as Timestamp?,
      endedAt: json['endedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'initiatorId': initiatorId,
      'memberIds': memberIds,
      'status': status.name,
      'isVideo': isVideo,
      'maxParticipants': maxParticipants,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'endedAt': endedAt,
    };
  }
}

/// グループ通話の参加者1人分（`groupCalls/{id}/participants/{userId}`）。
class CallParticipant {
  const CallParticipant({
    required this.userId,
    required this.rhingId,
    this.micMuted = false,
    this.cameraOff = false,
    this.joinedAt,
    this.lastSeenAt,
  });

  final String userId;
  final String rhingId;
  final bool micMuted;
  final bool cameraOff;
  final Timestamp? joinedAt;

  /// 在室確認用のハートビート。Firestoreには切断検知の仕組みがないため、
  /// 在室中はクライアントが定期的にこの値を更新し、他の参加者は一定時間
  /// 更新が無い相手を離脱扱いにする。
  final Timestamp? lastSeenAt;

  factory CallParticipant.fromJson(String userId, Map<String, dynamic> json) {
    return CallParticipant(
      userId: userId,
      rhingId: json['rhingId'] as String,
      micMuted: json['micMuted'] as bool? ?? false,
      cameraOff: json['cameraOff'] as bool? ?? false,
      joinedAt: json['joinedAt'] as Timestamp?,
      lastSeenAt: json['lastSeenAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rhingId': rhingId,
      'micMuted': micMuted,
      'cameraOff': cameraOff,
      'joinedAt': joinedAt ?? FieldValue.serverTimestamp(),
      'lastSeenAt': lastSeenAt ?? FieldValue.serverTimestamp(),
    };
  }
}

/// 参加者2人ぶんのペア単位のシグナリング（`groupCalls/{id}/peerLinks/{pairId}`）。
/// メッシュ型はN人ぶんのペアそれぞれで個別にoffer/answer/ICE candidateの
/// やり取りが必要になるため、1対1の`Call.offer`/`Call.answer`のような
/// 単一フィールドではなく、ペアごとに独立したドキュメントを持つ。
class CallPeerLink {
  const CallPeerLink({
    required this.pairId,
    required this.userAId,
    required this.userBId,
    this.offer,
    this.answer,
    this.updatedAt,
  });

  final String pairId;

  /// 辞書順で小さい方のuserId＝オファー役。
  final String userAId;

  /// 辞書順で大きい方のuserId＝応答役。
  final String userBId;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final Timestamp? updatedAt;

  /// 2人のuserIdから決定的なpairIdを作る（順序に依存しない）。
  /// `userAId`は常に辞書順で小さい方になる＝そちらがオファー役という
  /// 決定的なルールにすることで、両者が同時にofferを作ってしまう衝突を防ぐ。
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  factory CallPeerLink.fromJson(String pairId, Map<String, dynamic> json) {
    return CallPeerLink(
      pairId: pairId,
      userAId: json['userAId'] as String,
      userBId: json['userBId'] as String,
      offer: (json['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (json['answer'] as Map?)?.cast<String, dynamic>(),
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userAId': userAId,
      'userBId': userBId,
      'offer': offer,
      'answer': answer,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
