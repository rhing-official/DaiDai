/// 一対・広場に対する個人的な表示設定（`users/{userId}/conversationPrefs/{conversationId}`）。
/// conversationIdはdmIdまたはgroupId。相手には一切公開されない。
class ConversationPrefs {
  const ConversationPrefs({
    this.pinned = false,
    this.notificationsMuted = false,
  });

  final bool pinned;
  final bool notificationsMuted;

  static const none = ConversationPrefs();

  ConversationPrefs copyWith({
    bool? pinned,
    bool? notificationsMuted,
  }) {
    return ConversationPrefs(
      pinned: pinned ?? this.pinned,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
    );
  }

  factory ConversationPrefs.fromJson(Map<String, dynamic> json) {
    return ConversationPrefs(
      pinned: json['pinned'] as bool? ?? false,
      notificationsMuted: json['notificationsMuted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'notificationsMuted': notificationsMuted,
    };
  }
}
