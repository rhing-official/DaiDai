import 'package:cloud_firestore/cloud_firestore.dart';

import 'group_profile_card.dart';

/// 広場（Group） - 3人以上のグループチャット
class Group {
  const Group({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.memberRoles,
    required this.defaultRoomId,
    this.profileCard,
    this.createdAt,
  });

  final String groupId;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  /// userId -> role (owner | moderator | member)
  final Map<String, String> memberRoles;
  final String defaultRoomId;

  /// 広場を代表するプロフィールカード（最大1枚）。未作成ならnull。
  /// メンバー全員が編集できる（`_ProfileTabState`の個人カードとは異なり
  /// 所有者・モデレーター限定ではない）。
  final GroupProfileCard? profileCard;

  final Timestamp? createdAt;

  factory Group.fromJson(String groupId, Map<String, dynamic> json) {
    final profileCardJson = json['profileCard'] as Map<String, dynamic>?;
    return Group(
      groupId: groupId,
      name: json['name'] as String,
      ownerId: json['ownerId'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      memberRoles: Map<String, String>.from(json['memberRoles'] as Map),
      defaultRoomId: json['defaultRoomId'] as String,
      profileCard: profileCardJson != null
          ? GroupProfileCard.fromJson(profileCardJson)
          : null,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'memberRoles': memberRoles,
      'defaultRoomId': defaultRoomId,
      'profileCard': profileCard?.toJson(),
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}

/// お部屋（Room） - 広場内の実際に会話する場所。
/// フェーズ1では節（カテゴリ）機能は使わず、広場作成時に1つだけ自動生成する。
class Room {
  const Room({
    required this.roomId,
    required this.groupId,
    required this.name,
    required this.memberIds,
    this.lastMessageAt,
  });

  final String roomId;
  final String groupId;
  final String name;
  /// 広場のmemberIdsを非正規化して保持（セキュリティルールでの参照を単純化するため）。
  final List<String> memberIds;
  final Timestamp? lastMessageAt;

  factory Room.fromJson(String roomId, Map<String, dynamic> json) {
    return Room(
      roomId: roomId,
      groupId: json['groupId'] as String,
      name: json['name'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'name': name,
      'memberIds': memberIds,
      'lastMessageAt': lastMessageAt,
    };
  }
}
