class AppUser {
  const AppUser({
    required this.userId,
    required this.rhingId,
    this.displayName,
  });

  final String userId;
  final String rhingId;
  final String? displayName;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: json['userId'] as String,
      rhingId: json['rhingId'] as String,
      displayName: json['displayName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'rhingId': rhingId,
      'displayName': displayName,
    };
  }
}
