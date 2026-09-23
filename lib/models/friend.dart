import 'package:cloud_firestore/cloud_firestore.dart';

/// 友達関係（`users/{userId}/friends/{friendUserId}`）。
/// 友達申請が承認されたときに、双方のuserIdの下にそれぞれ1件ずつ作られる。
class Friend {
  const Friend({
    required this.friendUserId,
    required this.friendRhingSeed,
    this.addedAt,
  });

  final String friendUserId;
  final String friendRhingSeed;
  final Timestamp? addedAt;

  factory Friend.fromJson(String friendUserId, Map<String, dynamic> json) {
    return Friend(
      friendUserId: friendUserId,
      friendRhingSeed: json['friendRhingSeed'] as String,
      addedAt: json['addedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'friendRhingSeed': friendRhingSeed,
      'addedAt': addedAt ?? FieldValue.serverTimestamp(),
    };
  }
}
