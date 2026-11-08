/// 端末をまたいで同期する表示設定（設定タブのうち、SharedPreferencesだけで
/// 完結していた項目をFirestoreにも保存したもの）。
///
/// 各フィールドがnullなのは「まだどの端末でもこの設定を変更したことが無い」
/// ことを表す。ログイン時、nullのフィールドは同期対象から外れ、端末側の
/// 現在値（SharedPreferences由来）がそのまま使われる（[UserRepository]の
/// 利用側・`applyRemoteUserPreferences`参照）。値はSharedPreferencesに
/// 保存している文字列/int表現とそのまま同じものを使う。
class AppUserPreferences {
  const AppUserPreferences({
    this.accentColorArgb,
    this.accentColorsArgb,
    this.gekigaBackgroundColorArgb,
    this.themeMode,
    this.localeCode,
    this.sendKeyMode,
    this.stickerSendMode,
    this.draftSyncEnabled,
    this.joinVideoCameraOn,
    this.iconSplitMirrored,
    this.slidePickEnabled,
    this.chatLayoutStyle,
    this.slideTransitionStyle,
    this.messageTimeFormat,
    this.appUiStyle,
    this.customAccentColorsArgb,
    this.customFontColorsArgb,
    this.removedDefaultColorPresetsHex,
    this.conversationSortOrder,
    this.fontDesign,
    this.ringtoneSound,
    this.callingSound,
    this.notificationSound,
    this.textColorLightArgb,
    this.textColorDarkArgb,
    this.onAccentColorArgb,
    this.calendarWeekStart,
    this.calendarSystem,
    this.holidayRegions,
    this.holidayObservances,
    this.holidayReligions,
    this.guideSeen,
  });

  static const empty = AppUserPreferences();

  final int? accentColorArgb;

  /// UIスタイル別のアクセントカラー（2026-11-08追加、キーは`AppUiStyle.name`）。
  /// 無いスタイルは旧来の共通の[accentColorArgb]に従う。
  final Map<String, int>? accentColorsArgb;
  final int? gekigaBackgroundColorArgb;
  final String? themeMode;
  final String? localeCode;
  final String? sendKeyMode;
  final String? stickerSendMode;
  final bool? draftSyncEnabled;

  /// ビデオ通話に応答・参加した時にカメラをオンで入るか（2026-11-01追加、null=標準のオン）。
  final bool? joinVideoCameraOn;

  /// 「アイコン＋寄合一覧」を左右反転するか（2026-11-01、nullは標準のオフ）。
  final bool? iconSplitMirrored;

  /// 押したまま指を滑らせて選ぶ操作を使うか（2026-11-05追加、null=標準のオン）。
  final bool? slidePickEnabled;

  final String? chatLayoutStyle;

  /// 画面遷移の動きの種類（2026-11-04追加、null=標準の「スライド＋滲み」）。
  final String? slideTransitionStyle;

  final String? messageTimeFormat;
  final String? appUiStyle;

  /// ユーザーが自分で登録したアクセントカラーの一覧（`accentColorArgb`
  /// とは別に、繰り返し使うために保存した色。2026-08-29追加）。
  final List<int>? customAccentColorsArgb;

  /// カードの文字色の登録色（2026-10-31追加、[customAccentColorsArgb]と同じ形式）。
  final List<int>? customFontColorsArgb;

  /// ユーザーが長押しで削除した固定プリセットのhex文字列一覧
  /// （設定タブ`_kDefaultColorPresets`の要素のうち非表示化されたもの。
  /// 復活させる手段は無い、2026-09-15追加）。
  final List<String>? removedDefaultColorPresetsHex;

  /// 語らい一覧の並べ替え順（`ConversationSortOrder`のname、2026-09-02追加）。
  final String? conversationSortOrder;

  /// フォントデザイン（`FontDesign`のname、2026-09-06追加）。
  final String? fontDesign;

  /// 着信音（`SoundPreset.id`、又は`http`で始まるカスタムアップロード音源の
  /// ダウンロードURL、2026-09-06追加）。
  final String? ringtoneSound;

  /// 呼出音（発信者が相手の応答を待つ間に聞く音。値の形式は[ringtoneSound]と
  /// 同じ、2026-09-06追加）。
  final String? callingSound;

  /// 通知音（メッセージ受信音、Androidのみ対応。値の形式は[ringtoneSound]と
  /// 同じ、2026-09-06 Phase B追加）。
  final String? notificationSound;

  /// ユーザーが指定した文字色（フラット/ガラスの`colorScheme.onSurface`
  /// 相当、2026-09-14追加）。アクセントカラーと異なり背景とのコントラストが
  /// 直接可読性に関わる為、ライト/ダークで別々に保存する。
  final int? textColorLightArgb;
  final int? textColorDarkArgb;

  /// アクセント上の文字色（0は自動）。
  final int? onAccentColorArgb;

  /// カレンダーの週の始まり（`CalendarWeekStart`のname、2026-10-04追加）。
  final String? calendarWeekStart;

  /// カレンダーの全体の暦（`CalendarSystem`のname、2026-11-05追加）。
  final String? calendarSystem;

  /// カレンダーに出す祝日・祭日・宗教上の祝日の選択（2026-11-05追加）。
  /// regionsがnullなら居住国に従う。
  final List<String>? holidayRegions;
  final bool? holidayObservances;
  final List<String>? holidayReligions;

  /// 初回の使い方ガイドの視聴状況（2026-10-17追加）。表示設定ではなく通過儀礼の
  /// 記録で、アカウント毎に持つ（別の端末でも再表示しない）。**null＝既存住人
  /// （この機能の追加前に登録済みで、初回ガイドは出さない）／false＝新規登録で
  /// 未視聴／true＝視聴済みまたはスキップ済み**。新規作成時に`false`で保存する。
  final bool? guideSeen;

  factory AppUserPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return AppUserPreferences(
      accentColorArgb: json['accentColorArgb'] as int?,
      accentColorsArgb: (json['accentColorsArgb'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, (value as num).toInt())),
      gekigaBackgroundColorArgb: json['gekigaBackgroundColorArgb'] as int?,
      themeMode: json['themeMode'] as String?,
      localeCode: json['localeCode'] as String?,
      sendKeyMode: json['sendKeyMode'] as String?,
      stickerSendMode: json['stickerSendMode'] as String?,
      draftSyncEnabled: json['draftSyncEnabled'] as bool?,
      joinVideoCameraOn: json['joinVideoCameraOn'] as bool?,
      iconSplitMirrored: json['iconSplitMirrored'] as bool?,
      slidePickEnabled: json['slidePickEnabled'] as bool?,
      chatLayoutStyle: json['chatLayoutStyle'] as String?,
      slideTransitionStyle: json['slideTransitionStyle'] as String?,
      messageTimeFormat: json['messageTimeFormat'] as String?,
      appUiStyle: json['appUiStyle'] as String?,
      customAccentColorsArgb: (json['customAccentColorsArgb'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      customFontColorsArgb: (json['customFontColorsArgb'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      removedDefaultColorPresetsHex:
          (json['removedDefaultColorPresetsHex'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      conversationSortOrder: json['conversationSortOrder'] as String?,
      fontDesign: json['fontDesign'] as String?,
      ringtoneSound: json['ringtoneSound'] as String?,
      callingSound: json['callingSound'] as String?,
      notificationSound: json['notificationSound'] as String?,
      textColorLightArgb: json['textColorLightArgb'] as int?,
      textColorDarkArgb: json['textColorDarkArgb'] as int?,
      onAccentColorArgb: json['onAccentColorArgb'] as int?,
      calendarWeekStart: json['calendarWeekStart'] as String?,
      calendarSystem: json['calendarSystem'] as String?,
      holidayRegions: (json['holidayRegions'] as List?)?.cast<String>(),
      holidayObservances: json['holidayObservances'] as bool?,
      holidayReligions: (json['holidayReligions'] as List?)?.cast<String>(),
      guideSeen: json['guideSeen'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (accentColorArgb != null) 'accentColorArgb': accentColorArgb,
      if (accentColorsArgb != null) 'accentColorsArgb': accentColorsArgb,
      if (gekigaBackgroundColorArgb != null)
        'gekigaBackgroundColorArgb': gekigaBackgroundColorArgb,
      if (themeMode != null) 'themeMode': themeMode,
      if (localeCode != null) 'localeCode': localeCode,
      if (sendKeyMode != null) 'sendKeyMode': sendKeyMode,
      if (stickerSendMode != null) 'stickerSendMode': stickerSendMode,
      if (draftSyncEnabled != null) 'draftSyncEnabled': draftSyncEnabled,
      if (joinVideoCameraOn != null) 'joinVideoCameraOn': joinVideoCameraOn,
      if (iconSplitMirrored != null) 'iconSplitMirrored': iconSplitMirrored,
      if (slidePickEnabled != null) 'slidePickEnabled': slidePickEnabled,
      if (chatLayoutStyle != null) 'chatLayoutStyle': chatLayoutStyle,
      if (slideTransitionStyle != null)
        'slideTransitionStyle': slideTransitionStyle,
      if (messageTimeFormat != null) 'messageTimeFormat': messageTimeFormat,
      if (appUiStyle != null) 'appUiStyle': appUiStyle,
      if (customAccentColorsArgb != null)
        'customAccentColorsArgb': customAccentColorsArgb,
      if (customFontColorsArgb != null)
        'customFontColorsArgb': customFontColorsArgb,
      if (removedDefaultColorPresetsHex != null)
        'removedDefaultColorPresetsHex': removedDefaultColorPresetsHex,
      if (conversationSortOrder != null)
        'conversationSortOrder': conversationSortOrder,
      if (fontDesign != null) 'fontDesign': fontDesign,
      if (ringtoneSound != null) 'ringtoneSound': ringtoneSound,
      if (callingSound != null) 'callingSound': callingSound,
      if (notificationSound != null) 'notificationSound': notificationSound,
      if (textColorLightArgb != null) 'textColorLightArgb': textColorLightArgb,
      if (textColorDarkArgb != null) 'textColorDarkArgb': textColorDarkArgb,
      if (onAccentColorArgb != null) 'onAccentColorArgb': onAccentColorArgb,
      if (calendarWeekStart != null) 'calendarWeekStart': calendarWeekStart,
      if (calendarSystem != null) 'calendarSystem': calendarSystem,
      if (holidayRegions != null) 'holidayRegions': holidayRegions,
      if (holidayObservances != null) 'holidayObservances': holidayObservances,
      if (holidayReligions != null) 'holidayReligions': holidayReligions,
      if (guideSeen != null) 'guideSeen': guideSeen,
    };
  }
}
