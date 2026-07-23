import 'package:cloud_firestore/cloud_firestore.dart';

/// 友達関係（`users/{userId}/friends/{friendUserId}`）。
/// 友達申請が承認されたときに、双方のuserIdの下にそれぞれ1件ずつ作られる。
class Friend {
  const Friend({
    required this.friendUserId,
    required this.friendRhingId,
    this.addedAt,
  });

  final String friendUserId;
  final String friendRhingId;
  final Timestamp? addedAt;

  factory Friend.fromJson(String friendUserId, Map<String, dynamic> json) {
    return Friend(
      friendUserId: friendUserId,
      friendRhingId: json['friendRhingId'] as String,
      addedAt: json['addedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'friendRhingId': friendRhingId,
      'addedAt': addedAt ?? FieldValue.serverTimestamp(),
    };
  }
}
