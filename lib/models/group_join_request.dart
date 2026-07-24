import 'package:cloud_firestore/cloud_firestore.dart';

/// 広場への参加リクエストの状態。
/// pending: 承認待ち, accepted: 承認済み（参加済み）, declined: 却下済み（再申請可）
enum GroupJoinRequestStatus {
  pending,
  accepted,
  declined;

  static GroupJoinRequestStatus fromName(String name) {
    return GroupJoinRequestStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => GroupJoinRequestStatus.pending,
    );
  }
}

/// 招待リンクから広場に参加するための承認待ちリクエスト。
/// `groups/{groupId}/joinRequests/{requesterId}`に保存され、1人につき
/// ドキュメントは常に1つだけ存在する（却下後の再申請も同じドキュメントを更新する）。
class GroupJoinRequest {
  const GroupJoinRequest({
    required this.requestId,
    required this.groupId,
    required this.requesterId,
    required this.requesterRhingId,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  final String requestId;
  final String groupId;
  final String requesterId;
  final String requesterRhingId;
  final GroupJoinRequestStatus status;
  final Timestamp? createdAt;
  final Timestamp? respondedAt;

  factory GroupJoinRequest.fromJson(
    String requestId,
    Map<String, dynamic> json,
  ) {
    return GroupJoinRequest(
      requestId: requestId,
      groupId: json['groupId'] as String,
      requesterId: json['requesterId'] as String,
      requesterRhingId: json['requesterRhingId'] as String,
      status: GroupJoinRequestStatus.fromName(json['status'] as String),
      createdAt: json['createdAt'] as Timestamp?,
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'requesterId': requesterId,
      'requesterRhingId': requesterRhingId,
      'status': status.name,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'respondedAt': respondedAt,
    };
  }
}
