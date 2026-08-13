/// 一対・広場に対する個人的な表示設定（`users/{userId}/conversationPrefs/{conversationId}`）。
/// conversationIdはdmIdまたはgroupId。相手には一切公開されない。
class ConversationPrefs {
  const ConversationPrefs({
    this.pinned = false,
    this.notificationsMuted = false,
    this.roomNotificationOverrides = const {},
    this.draftByRoom = const {},
  });

  final bool pinned;
  final bool notificationsMuted;

  /// 広場の寄合ごとの通知オフの上書き（roomId→muted）。対象の寄合が
  /// `Room.customSettingsEnabled`の間のみ参照され、[notificationsMuted]
  /// （広場全体の既定値）より優先される（2026-07-29追加）。
  final Map<String, bool> roomNotificationOverrides;

  /// 寄合ごとのメッセージ入力欄の下書き（roomId→本文）。複数端末同期設定
  /// （`draftSyncEnabledProvider`）がオンの間、`ChatScreen`が画面を開いた
  /// 時に読み込み・デバウンス保存する（2026-08-13追加）。
  final Map<String, String> draftByRoom;

  static const none = ConversationPrefs();

  ConversationPrefs copyWith({
    bool? pinned,
    bool? notificationsMuted,
    Map<String, bool>? roomNotificationOverrides,
    Map<String, String>? draftByRoom,
  }) {
    return ConversationPrefs(
      pinned: pinned ?? this.pinned,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
      roomNotificationOverrides:
          roomNotificationOverrides ?? this.roomNotificationOverrides,
      draftByRoom: draftByRoom ?? this.draftByRoom,
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
      draftByRoom: (json['draftByRoom'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key as String, value as String),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'notificationsMuted': notificationsMuted,
      'roomNotificationOverrides': roomNotificationOverrides,
      'draftByRoom': draftByRoom,
    };
  }
}
