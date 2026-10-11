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
    required this.requesterRhingSeed,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  final String requestId;
  final String groupId;
  final String requesterId;
  final String requesterRhingSeed;
  final GroupJoinRequestStatus status;
  final Timestamp? createdAt;
  final Timestamp? respondedAt;

  factory GroupJoinRequest.fromJson(
    String requestId,
    Map<String, dynamic> json,
  ) {
    // 古い・欠けたドキュメントでも落ちないようにする（2026-10-11）。招待URL
    // から参加画面を開いた時、2026-09-23のRhing ID→Rhing Seed改名より前に
    // 作られたリクエスト（旧フィールド名`requesterRhingId`のみ）を読んで
    // `null as String`の例外になり、参加画面が開けなくなっていた。
    return GroupJoinRequest(
      requestId: requestId,
      groupId: json['groupId'] as String? ?? '',
      requesterId: json['requesterId'] as String? ?? requestId,
      requesterRhingSeed:
          (json['requesterRhingSeed'] as String?) ??
          (json['requesterRhingId'] as String?) ??
          '',
      status: GroupJoinRequestStatus.fromName(json['status'] as String? ?? ''),
      createdAt: json['createdAt'] as Timestamp?,
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'requesterId': requesterId,
      'requesterRhingSeed': requesterRhingSeed,
      'status': status.name,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'respondedAt': respondedAt,
    };
  }
}
