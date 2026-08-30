import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対（DirectMessage）の寄合（テキストチャンネル）。
class DmRoom {
  const DmRoom({
    required this.roomId,
    required this.dmId,
    required this.name,
    required this.participants,
    this.lastMessageAt,
    this.createdAt,
    this.deletionRequestedBy,
    this.pinnedMessageIds = const [],
  });

  final String roomId;
  final String dmId;
  final String name;

  /// 親のDirectMessage.participantsを非正規化して保持する
  /// （広場のRoom.memberIdsと同じ理由: セキュリティルールでの参照を
  /// 単純化するため。特にDM作成と同じバッチ内でこの寄合を作成する際、
  /// ルール側が親ドキュメントをget()すると未コミット状態を見てしまい
  /// permission-deniedになるため、自己完結した条件にする必要がある）。
  final List<String> participants;

  final Timestamp? lastMessageAt;

  /// 寄合一覧の並び順（作成順）に使う。
  final Timestamp? createdAt;

  /// この寄合の削除を実行中の参加者のuserId。nullなら削除中でない通常
  /// 状態。削除操作の間だけ立てるマーカーで、これが立っている間は
  /// 参加者なら誰でもこの寄合のメッセージを物理削除できる
  /// （`DirectMessageRepository.deleteRoom`、firestore.rules参照）。
  final String? deletionRequestedBy;

  /// ピン留めされたメッセージidの一覧。配列の末尾が最後にピン留めしたもの
  /// （表示時は逆順にして新しいピン留めを上に出す）。
  final List<String> pinnedMessageIds;

  factory DmRoom.fromJson(String roomId, Map<String, dynamic> json) {
    final pinnedJson = json['pinnedMessageIds'];
    return DmRoom(
      roomId: roomId,
      dmId: json['dmId'] as String,
      name: json['name'] as String,
      participants: List<String>.from(json['participants'] as List),
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
      createdAt: json['createdAt'] as Timestamp?,
      deletionRequestedBy: json['deletionRequestedBy'] as String?,
      pinnedMessageIds: pinnedJson is List
          ? List<String>.from(pinnedJson)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dmId': dmId,
      'name': name,
      'participants': participants,
      'lastMessageAt': lastMessageAt,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'deletionRequestedBy': deletionRequestedBy,
      'pinnedMessageIds': pinnedMessageIds,
    };
  }
}
