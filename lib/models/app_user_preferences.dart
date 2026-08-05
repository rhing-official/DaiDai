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
    this.terminologyStyle,
    this.sendKeyMode,
    this.chatLayoutStyle,
    this.messageTimeFormat,
    this.appUiStyle,
  });

  static const empty = AppUserPreferences();

  final int? accentColorArgb;
  final int? gekigaBackgroundColorArgb;
  final String? themeMode;
  final String? localeCode;
  final String? terminologyStyle;
  final String? sendKeyMode;
  final String? chatLayoutStyle;
  final String? messageTimeFormat;
  final String? appUiStyle;

  factory AppUserPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return AppUserPreferences(
      accentColorArgb: json['accentColorArgb'] as int?,
      gekigaBackgroundColorArgb: json['gekigaBackgroundColorArgb'] as int?,
      themeMode: json['themeMode'] as String?,
      localeCode: json['localeCode'] as String?,
      terminologyStyle: json['terminologyStyle'] as String?,
      sendKeyMode: json['sendKeyMode'] as String?,
      chatLayoutStyle: json['chatLayoutStyle'] as String?,
      messageTimeFormat: json['messageTimeFormat'] as String?,
      appUiStyle: json['appUiStyle'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (accentColorArgb != null) 'accentColorArgb': accentColorArgb,
      if (gekigaBackgroundColorArgb != null)
        'gekigaBackgroundColorArgb': gekigaBackgroundColorArgb,
      if (themeMode != null) 'themeMode': themeMode,
      if (localeCode != null) 'localeCode': localeCode,
      if (terminologyStyle != null) 'terminologyStyle': terminologyStyle,
      if (sendKeyMode != null) 'sendKeyMode': sendKeyMode,
      if (chatLayoutStyle != null) 'chatLayoutStyle': chatLayoutStyle,
      if (messageTimeFormat != null) 'messageTimeFormat': messageTimeFormat,
      if (appUiStyle != null) 'appUiStyle': appUiStyle,
    };
  }
}
