import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対（DirectMessage） - 1対1の会話空間
class DirectMessage {
  const DirectMessage({
    required this.dmId,
    required this.participants,
    required this.participantRhingIds,
    this.lastMessageAt,
    this.severanceRequestedBy,
  });

  final String dmId;
  final List<String> participants;
  /// userId -> rhingId。一覧表示で相手の名前を出すための非正規化データ。
  final Map<String, String> participantRhingIds;
  final Timestamp? lastMessageAt;

  /// 絶縁（双方合意による友達関係の解消・会話履歴の完全削除）を提案した側の
  /// userId。nullなら提案なし。提案した本人以外の参加者が同意すると、
  /// [DirectMessageRepository.acceptSeverance]がこのフラグを根拠に
  /// メッセージ・friends・friendRequests・この一対自体を物理削除する。
  final String? severanceRequestedBy;

  /// 自分以外の参加者のuserId。
  String otherUserId(String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId);
  }

  /// 自分以外の参加者のRhing ID。
  String otherRhingId(String currentUserId) {
    final otherId = otherUserId(currentUserId);
    return participantRhingIds[otherId] ?? otherId;
  }

  factory DirectMessage.fromJson(String dmId, Map<String, dynamic> json) {
    return DirectMessage(
      dmId: dmId,
      participants: List<String>.from(json['participants'] as List),
      participantRhingIds: Map<String, String>.from(
        json['participantRhingIds'] as Map? ?? {},
      ),
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
      severanceRequestedBy: json['severanceRequestedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participants': participants,
      'participantRhingIds': participantRhingIds,
      'lastMessageAt': lastMessageAt,
      'severanceRequestedBy': severanceRequestedBy,
    };
  }

  /// 2人のuserIdから決定的なdmIdを作る（順序に依存しない）
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
