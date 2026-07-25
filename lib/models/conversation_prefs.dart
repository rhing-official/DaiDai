/// 一対・広場に対する個人的な表示設定（`users/{userId}/conversationPrefs/{conversationId}`）。
/// conversationIdはdmIdまたはgroupId。相手には一切公開されない。
class ConversationPrefs {
  const ConversationPrefs({
    this.pinned = false,
    this.notificationsMuted = false,
    this.readReceiptsEnabled = true,
  });

  final bool pinned;
  final bool notificationsMuted;

  /// この会話で既読機能（自分の既読の送信・相手の既読の表示）を使うかどうか。
  final bool readReceiptsEnabled;

  static const none = ConversationPrefs();

  ConversationPrefs copyWith({
    bool? pinned,
    bool? notificationsMuted,
    bool? readReceiptsEnabled,
  }) {
    return ConversationPrefs(
      pinned: pinned ?? this.pinned,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
    );
  }

  factory ConversationPrefs.fromJson(Map<String, dynamic> json) {
    return ConversationPrefs(
      pinned: json['pinned'] as bool? ?? false,
      notificationsMuted: json['notificationsMuted'] as bool? ?? false,
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'notificationsMuted': notificationsMuted,
      'readReceiptsEnabled': readReceiptsEnabled,
    };
  }
}
