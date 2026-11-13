/// 着信音・呼出音・通知音のカスタマイズ機能で使う音源の種別
/// （2026-09-06追加、`notification`は同日Phase Bとして追加）。
///
/// 着信音・呼出音はDaiDaiが既にOSのプッシュ通知を経由せず`CallSoundPlayer`
/// （audioplayers）でローカル再生している為、プラットフォームのOS制約を
/// 受けず同梱プリセット＋端末からのアップロードの両方に対応出来る。
/// 一方通知音は実際のOSプッシュ通知を経由する為、iOS/Web/Windows/Linux/
/// macOSでは技術的制約又はプッシュ通知自体が未実装のため対象外とし、
/// Androidのみ同梱プリセット＋アップロードに対応する（`android_notification_
/// sound_sync.dart`・`push_notifications.dart`参照）。`notification`の
/// プリセット`id`はそのままAndroidのraw resource名として使う規約にしている
/// （`android/app/src/main/res/raw/`配下のファイル名と一致させること）。
enum SoundCategory { ringtone, calling, notification }

/// 同梱されている選択肢1件。表示名は`Strings`側（`settings_tab.dart`の
/// `soundPresetLabel`）で日英切り替えする為、ここでは持たない
/// （`FontDesign`の表示名がモデルではなく設定UI側の`labelFor`に
/// あるのと同じ考え方）。
class SoundPreset {
  const SoundPreset({required this.id, required this.assetPath});

  /// 保存値として使う識別子（`AppUserPreferences.ringtoneSound`/
  /// `callingSound`にそのまま入る）。
  final String id;

  /// `AssetSource`にそのまま渡せる、`assets/`を含まない相対パス
  /// （`CallSoundAsset.assetPath`と同じ形式）。
  final String assetPath;
}

/// 着信音・呼出音で共通に選べるプリセット一覧（2026-09-12本番音源に差し替え、
/// 着信音・呼出音はユーザー判断で選択肢自体を共通化した。どちらを選ぶかは
/// `ringtoneSoundProvider`/`callingSoundProvider`で個別に保存されるが、
/// 選べる音源のリストは同じもの）。BigSoundBank（CC0）・Mixkit（Free
/// License）の音源、詳細は`assets/sounds/LICENSE.md`参照。
const _callTonePresets = [
  SoundPreset(id: 'phonebooth_ring', assetPath: 'sounds/phonebooth_ring.mp3'),
  SoundPreset(id: 'marimba_ring', assetPath: 'sounds/marimba_ring.mp3'),
  SoundPreset(
    id: 'european_ringback',
    assetPath: 'sounds/european_ringback.mp3',
  ),
  SoundPreset(id: 'futuristic_dial', assetPath: 'sounds/futuristic_dial.mp3'),
];

/// 通知音のプリセット一覧（2026-09-12本番音源に差し替え）。idはそのまま
/// Androidのraw resource名として使う規約（`android/app/src/main/res/raw/`
/// 配下のファイル名と一致させること、[androidNotificationChannelIdFor]と
/// `push_notifications.dart`の`_notificationChannels`参照）。
const _notificationPresets = [
  SoundPreset(
    id: 'notification_lasomarie',
    assetPath: 'sounds/notification_lasomarie.mp3',
  ),
  SoundPreset(
    id: 'notification_message_pop',
    assetPath: 'sounds/notification_message_pop.mp3',
  ),
  SoundPreset(
    id: 'notification_happy_bells',
    assetPath: 'sounds/notification_happy_bells.mp3',
  ),
];

extension SoundCategoryPresets on SoundCategory {
  /// このカテゴリで選べるプリセット一覧。着信音・呼出音は選択肢を共通化
  /// している（設定自体は`AppUserPreferences.ringtoneSound`/`callingSound`
  /// で個別に保存される）。
  List<SoundPreset> get presets => switch (this) {
    SoundCategory.ringtone || SoundCategory.calling => _callTonePresets,
    SoundCategory.notification => _notificationPresets,
  };

  /// 未設定時の標準の音。着信音・呼出音はマリンバ（2026-10-21、ユーザー指示）、
  /// 通知音は一覧の先頭。保存値が既にある人の設定は変わらない。
  SoundPreset get defaultPreset => switch (this) {
    SoundCategory.ringtone || SoundCategory.calling =>
      _callTonePresets.firstWhere((p) => p.id == 'marimba_ring'),
    SoundCategory.notification => presets.first,
  };

  /// 保存値（プリセットID又は`http`で始まるカスタムアップロード音源の
  /// ダウンロードURL）を、実際に再生出来るソース文字列に解決する。
  /// プリセットIDは`AssetSource`用の相対パスへ変換し、URLはそのまま返す
  /// （呼び出し側は`http`で始まるかどうかで`AssetSource`/`UrlSource`を
  /// 使い分ける、[CallSoundPlayer]参照）。
  String resolveSource(String? savedValue) {
    if (savedValue == null) return defaultPreset.assetPath;
    if (savedValue.startsWith('http')) return savedValue;
    final preset = presets.firstWhere(
      (p) => p.id == savedValue,
      orElse: () => defaultPreset,
    );
    return preset.assetPath;
  }
}

/// 通知音プリセットに対応するAndroid通知チャンネルID（`daidai_messages_<
/// プリセットid>`）。チャンネルは作成後に音を変更出来ない為、音の
/// 選択肢毎に別チャンネルを用意する方式にしている（`push_notifications.dart`・
/// `android_notification_sound_sync.dart`で共有、2026-09-06追加）。
String androidNotificationChannelIdFor(String presetId) =>
    'daidai_messages_$presetId';

/// カスタムアップロード通知音源用のチャンネルIDの接頭辞。旧版は固定ID
/// （`daidai_messages_custom`）だった。
const androidCustomNotificationChannelId = 'daidai_messages_custom';

/// カスタム音源のURL毎のチャンネルID（2026-11-13変更）。チャンネルの音は作成後に変えられず、
/// 同じIDの削除→再作成はAndroidが以前の設定（古い音・標準音）を復元することがあるため、
/// 音源が変わる（URLが変わる）たびに別のIDにする。
String androidCustomNotificationChannelIdFor(String url) =>
    '${androidCustomNotificationChannelId}_${customSoundKey(url)}';

/// URLから作る短い固定キー（FNV-1a、実行のたびに変わる`hashCode`は使わない）。
String customSoundKey(String url) {
  var hash = 0x811c9dc5;
  for (final unit in url.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
