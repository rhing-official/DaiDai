import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対・広場に対する個人的な表示設定（`users/{userId}/conversationPrefs/{conversationId}`）。
/// conversationIdはdmId又はgroupId。相手には一切公開されない。
class ConversationPrefs {
  const ConversationPrefs({
    this.pinned = false,
    this.notificationsMuted = false,
    this.roomNotificationOverrides = const {},
    this.draftByRoom = const {},
    this.lastReadAt,
    this.unreadCount = 0,
    this.unreadByRoom = const {},
    this.calendarSystem,
    this.calendarWeekStart,
    this.holidayOverride,
  });

  final bool pinned;
  final bool notificationsMuted;

  /// 自分がこの語らいを最後に開いて既読を付けた時刻。語らい一覧の
  /// 「未読優先」並べ替えで、`DirectMessage`/`Group`の`lastMessageAt`と
  /// 比較して未読かどうかを判定する為に使う（2026-09-02追加）。
  final Timestamp? lastReadAt;

  /// 未読メッセージ件数（語らい一覧のバッジ表示用、2026-09-02追加）。
  /// 相手からのメッセージ受信時にCloud Functions
  /// （`functions/src/index.ts`の`onDmMessageCreated`/`onGroupMessageCreated`）
  /// が加算し、自分がこの語らいを開いて既読を付けたタイミング
  /// （[ConversationPrefsRepository.setLastRead]）で0にリセットされる。
  final int unreadCount;

  /// 寄合毎の未読メッセージ件数（roomId→件数、寄合一覧のバッジ表示用、
  /// 2026-10-04追加）。[unreadCount]と同じく`incrementUnreadCounts`が加算し、
  /// その寄合を開いて既読を付けたタイミング（[ConversationPrefsRepository
  /// .setLastRead]の`roomId`指定）で該当キーだけ0に戻る。
  final Map<String, int> unreadByRoom;

  /// 広場の寄合毎の通知オフの上書き（roomId→muted）。対象の寄合が
  /// `Room.customSettingsEnabled`の間のみ参照され、[notificationsMuted]
  /// （広場全体の既定値）より優先される（2026-07-29追加）。
  final Map<String, bool> roomNotificationOverrides;

  /// 寄合毎のメッセージ入力欄の下書き（roomId→本文）。複数端末同期設定
  /// （`draftSyncEnabledProvider`）がオンの間、`ChatScreen`が画面を開いた
  /// 時に読み込み・デバウンス保存する（2026-08-13追加）。
  final Map<String, String> draftByRoom;

  /// この語らいのカレンダーに使う暦（`CalendarSystem.name`、2026-11-05追加）。
  /// nullなら全体の暦に従う。自分の表示にだけ効き、相手や予定のデータには影響しない。
  final String? calendarSystem;

  /// この語らいのカレンダーの週の始まり（`CalendarWeekStart.name`、2026-11-05追加）。
  /// nullなら標準（設定>語らい>カレンダー）に従う。
  final String? calendarWeekStart;

  /// この語らいの祝日・祭日・宗教上の祝日の選択（2026-11-05追加）。
  /// nullなら標準に従う。キーは`regions`（国コードの配列、省略可）・`observances`
  /// （bool）・`religions`（配列）。
  final Map<String, dynamic>? holidayOverride;

  static const none = ConversationPrefs();

  ConversationPrefs copyWith({
    bool? pinned,
    bool? notificationsMuted,
    Map<String, bool>? roomNotificationOverrides,
    Map<String, String>? draftByRoom,
    Timestamp? lastReadAt,
    int? unreadCount,
    Map<String, int>? unreadByRoom,
    String? calendarSystem,
    String? calendarWeekStart,
    Map<String, dynamic>? holidayOverride,
  }) {
    return ConversationPrefs(
      pinned: pinned ?? this.pinned,
      notificationsMuted: notificationsMuted ?? this.notificationsMuted,
      roomNotificationOverrides:
          roomNotificationOverrides ?? this.roomNotificationOverrides,
      draftByRoom: draftByRoom ?? this.draftByRoom,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      unreadCount: unreadCount ?? this.unreadCount,
      unreadByRoom: unreadByRoom ?? this.unreadByRoom,
      calendarSystem: calendarSystem ?? this.calendarSystem,
      calendarWeekStart: calendarWeekStart ?? this.calendarWeekStart,
      holidayOverride: holidayOverride ?? this.holidayOverride,
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
      lastReadAt: json['lastReadAt'] as Timestamp?,
      unreadCount: json['unreadCount'] as int? ?? 0,
      unreadByRoom: (json['unreadByRoom'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key as String, (value as num).toInt()),
      ),
      calendarSystem: json['calendarSystem'] as String?,
      calendarWeekStart: json['calendarWeekStart'] as String?,
      holidayOverride: (json['holidayOverride'] as Map?)
          ?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'notificationsMuted': notificationsMuted,
      'roomNotificationOverrides': roomNotificationOverrides,
      'draftByRoom': draftByRoom,
      'lastReadAt': lastReadAt,
      'unreadCount': unreadCount,
      'unreadByRoom': unreadByRoom,
      'calendarSystem': calendarSystem,
      'calendarWeekStart': calendarWeekStart,
      'holidayOverride': holidayOverride,
    };
  }
}
