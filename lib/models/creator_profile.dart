/// daidai横丁で出品したことのある人の公開プロフィール（`creatorProfiles/{userId}`、
/// 2026-11-28）。呼び名とアイコンだけを、横丁の一覧・詳細に出す。
class CreatorProfile {
  const CreatorProfile({required this.userId, this.nickname, this.iconUrl});

  final String userId;
  final String? nickname;
  final String? iconUrl;

  factory CreatorProfile.fromJson(String userId, Map<String, dynamic> json) {
    return CreatorProfile(
      userId: userId,
      nickname: json['nickname'] as String?,
      iconUrl: json['iconUrl'] as String?,
    );
  }
}
