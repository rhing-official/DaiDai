import 'package:cloud_firestore/cloud_firestore.dart';

/// 友達申請の状態。
/// pending: 返答待ち, accepted: 承認済み（友達）, declined: 拒否済み（再申請可）
enum FriendRequestStatus {
  pending,
  accepted,
  declined;

  static FriendRequestStatus fromName(String name) {
    return FriendRequestStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => FriendRequestStatus.pending,
    );
  }
}

/// 友達申請。2人のuserIdから決定的なidを作るため、1組の相手につき
/// ドキュメントは常に1つだけ存在する（拒否後の再申請も同じドキュメントを更新する）。
class FriendRequest {
  const FriendRequest({
    required this.requestId,
    required this.fromUserId,
    required this.fromRhingId,
    required this.toUserId,
    required this.toRhingId,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  final String requestId;
  final String fromUserId;
  final String fromRhingId;
  final String toUserId;
  final String toRhingId;
  final FriendRequestStatus status;
  final Timestamp? createdAt;
  final Timestamp? respondedAt;

  /// 自分以外の相手のRhing ID。
  String otherRhingId(String currentUserId) {
    return currentUserId == fromUserId ? toRhingId : fromRhingId;
  }

  factory FriendRequest.fromJson(String requestId, Map<String, dynamic> json) {
    return FriendRequest(
      requestId: requestId,
      fromUserId: json['fromUserId'] as String,
      fromRhingId: json['fromRhingId'] as String,
      toUserId: json['toUserId'] as String,
      toRhingId: json['toRhingId'] as String,
      status: FriendRequestStatus.fromName(json['status'] as String),
      createdAt: json['createdAt'] as Timestamp?,
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromUserId': fromUserId,
      'fromRhingId': fromRhingId,
      'toUserId': toUserId,
      'toRhingId': toRhingId,
      'status': status.name,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'respondedAt': respondedAt,
    };
  }

  /// 2人のuserIdから決定的なrequestIdを作る（順序に依存しない）。
  /// directMessagesのdmIdと同じ組み立て方にしており、
  /// Firestoreルール側で「一対を作るには対応する友達申請がaccepted済みであること」を
  /// 同じidで突き合わせて検証できるようにしている。
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
