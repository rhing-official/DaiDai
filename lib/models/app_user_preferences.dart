/// 端末をまたいで同期する表示設定（設定タブのうち、SharedPreferencesだけで
/// 完結していた項目をFirestoreにも保存したもの）。
///
/// 各フィールドがnullなのは「まだどの端末でもこの設定を変更したことがない」
/// ことを表す。ログイン時、nullのフィールドは同期対象から外れ、端末側の
/// 現在値（SharedPreferences由来）がそのまま使われる（[UserRepository]の
/// 利用側・`applyRemoteUserPreferences`参照）。値はSharedPreferencesに
/// 保存している文字列/int表現とそのまま同じものを使う。
class AppUserPreferences {
  const AppUserPreferences({
    this.accentColorArgb,
    this.gekigaBackgroundColorArgb,
    this.themeMode,
    this.localeCode,
    this.sendKeyMode,
    this.stickerSendMode,
    this.draftSyncEnabled,
    this.chatLayoutStyle,
    this.messageTimeFormat,
    this.appUiStyle,
    this.customAccentColorsArgb,
    this.conversationSortOrder,
    this.fontDesign,
    this.ringtoneSound,
    this.callingSound,
  });

  static const empty = AppUserPreferences();

  final int? accentColorArgb;
  final int? gekigaBackgroundColorArgb;
  final String? themeMode;
  final String? localeCode;
  final String? sendKeyMode;
  final String? stickerSendMode;
  final bool? draftSyncEnabled;
  final String? chatLayoutStyle;
  final String? messageTimeFormat;
  final String? appUiStyle;

  /// ユーザーが自分で登録したアクセントカラーの一覧（`accentColorArgb`
  /// とは別に、繰り返し使うために保存した色。2026-08-29追加）。
  final List<int>? customAccentColorsArgb;

  /// 語らい一覧の並べ替え順（`ConversationSortOrder`のname、2026-09-02追加）。
  final String? conversationSortOrder;

  /// フォントデザイン（`FontDesign`のname、2026-09-06追加）。
  final String? fontDesign;

  /// 着信音（`SoundPreset.id`、または`http`で始まるカスタムアップロード音源の
  /// ダウンロードURL、2026-09-06追加）。
  final String? ringtoneSound;

  /// 呼出音（発信者が相手の応答を待つ間に聞く音。値の形式は[ringtoneSound]と
  /// 同じ、2026-09-06追加）。
  final String? callingSound;

  factory AppUserPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return AppUserPreferences(
      accentColorArgb: json['accentColorArgb'] as int?,
      gekigaBackgroundColorArgb: json['gekigaBackgroundColorArgb'] as int?,
      themeMode: json['themeMode'] as String?,
      localeCode: json['localeCode'] as String?,
      sendKeyMode: json['sendKeyMode'] as String?,
      stickerSendMode: json['stickerSendMode'] as String?,
      draftSyncEnabled: json['draftSyncEnabled'] as bool?,
      chatLayoutStyle: json['chatLayoutStyle'] as String?,
      messageTimeFormat: json['messageTimeFormat'] as String?,
      appUiStyle: json['appUiStyle'] as String?,
      customAccentColorsArgb: (json['customAccentColorsArgb'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      conversationSortOrder: json['conversationSortOrder'] as String?,
      fontDesign: json['fontDesign'] as String?,
      ringtoneSound: json['ringtoneSound'] as String?,
      callingSound: json['callingSound'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (accentColorArgb != null) 'accentColorArgb': accentColorArgb,
      if (gekigaBackgroundColorArgb != null)
        'gekigaBackgroundColorArgb': gekigaBackgroundColorArgb,
      if (themeMode != null) 'themeMode': themeMode,
      if (localeCode != null) 'localeCode': localeCode,
      if (sendKeyMode != null) 'sendKeyMode': sendKeyMode,
      if (stickerSendMode != null) 'stickerSendMode': stickerSendMode,
      if (draftSyncEnabled != null) 'draftSyncEnabled': draftSyncEnabled,
      if (chatLayoutStyle != null) 'chatLayoutStyle': chatLayoutStyle,
      if (messageTimeFormat != null) 'messageTimeFormat': messageTimeFormat,
      if (appUiStyle != null) 'appUiStyle': appUiStyle,
      if (customAccentColorsArgb != null)
        'customAccentColorsArgb': customAccentColorsArgb,
      if (conversationSortOrder != null)
        'conversationSortOrder': conversationSortOrder,
      if (fontDesign != null) 'fontDesign': fontDesign,
      if (ringtoneSound != null) 'ringtoneSound': ringtoneSound,
      if (callingSound != null) 'callingSound': callingSound,
    };
  }
}
