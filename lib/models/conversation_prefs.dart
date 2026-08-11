/// 一対・広場に対する個人的な表示設定（`users/{userId}/conversationPrefs/{conversationId}`）。
/// conversationIdはdmIdまたはgroupId。相手には一切公開されない。
class ConversationPrefs {
  const ConversationPrefs({
    this.pinned = false,
    this.notificationsMuted = false,
    this.roomNotificationOverrides = const {},
  });

  final bool pinned;
  final bool notificationsMuted;

  /// 広場の寄合ごとの通知オフの上書き（roomId→muted）。対象の寄合が
  /// `Room.customSettingsEnabled`の間のみ参照され、[notificationsMuted]
  /// （広場全体の既定値）より優先される（2026-07-29追加）。
  final Map<String, bool> roomNotificationOverrides;

  static const none = ConversationPrefs();

  ConversationPrefs copyWith({
    bool? pinned,
    bool? notificationsMuted,
    Map<String, bool>? roomNotificationOverrides,
  }) {
    return ConversationPrefs(
      pinned: pinned ?? this.pinned,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
      roomNotificationOverrides:
          roomNotificationOverrides ?? this.roomNotificationOverrides,
    );
  }

  factory ConversationPrefs.fromJson(Map<String, dynamic> json) {
    return ConversationPrefs(
      pinned: json['pinned'] as bool? ?? false,
      notificationsMuted: json['notificationsMuted'] as bool? ?? false,
      roomNotificationOverrides:
          (json['roomNotificationOverrides'] as Map? ?? const {}).map(
            (key, value) => MapEntry(key as String, value as bool),
          ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'notificationsMuted': notificationsMuted,
      'roomNotificationOverrides': roomNotificationOverrides,
    };
  }
}
