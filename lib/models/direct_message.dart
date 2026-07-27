import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対（DirectMessage） - 1対1の会話空間
class DirectMessage {
  const DirectMessage({
    required this.dmId,
    required this.participants,
    required this.participantRhingIds,
    this.lastMessageAt,
    this.severanceRequestedBy,
    this.readReceiptsEnabled = true,
    this.readReceiptsProposalBy,
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

  /// 既読機能のオン/オフ（一対共有の1つの設定。個人ごとの非公開設定では
  /// ない）。変更にはどちら向きも相手の承認が必要（[readReceiptsProposalBy]
  /// 参照）。
  final bool readReceiptsEnabled;

  /// 既読オン/オフの変更を提案した側のuserId。nullなら提案なし。提案は
  /// 常に「現在の[readReceiptsEnabled]を反転させる」ことを意味する
  /// （severanceRequestedByと同じ最小構成。
  /// [DirectMessageRepository.proposeReadReceiptsToggle]/
  /// `acceptReadReceiptsToggle`参照）。
  final String? readReceiptsProposalBy;

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
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
      readReceiptsProposalBy: json['readReceiptsProposalBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participants': participants,
      'participantRhingIds': participantRhingIds,
      'lastMessageAt': lastMessageAt,
      'severanceRequestedBy': severanceRequestedBy,
      'readReceiptsEnabled': readReceiptsEnabled,
      'readReceiptsProposalBy': readReceiptsProposalBy,
    };
  }

  /// 2人のuserIdから決定的なdmIdを作る（順序に依存しない）
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
