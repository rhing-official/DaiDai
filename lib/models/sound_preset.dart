/// 着信音・呼出音・通知音のカスタマイズ機能で使う音源の種別
/// （2026-09-06追加、`notification`は同日Phase Bとして追加）。
///
/// 着信音・呼出音はDaiDaiが既にOSのプッシュ通知を経由せず`CallSoundPlayer`
/// （audioplayers）でローカル再生しているため、プラットフォームのOS制約を
/// 受けず同梱プリセット＋端末からのアップロードの両方に対応できる。
/// 一方通知音は実際のOSプッシュ通知を経由するため、iOS/Web/Windows/Linux/
/// macOSでは技術的制約またはプッシュ通知自体が未実装のため対象外とし、
/// Androidのみ同梱プリセット＋アップロードに対応する（`android_notification_
/// sound_sync.dart`・`push_notifications.dart`参照）。`notification`の
/// プリセット`id`はそのままAndroidのraw resource名として使う規約にしている
/// （`android/app/src/main/res/raw/`配下のファイル名と一致させること）。
enum SoundCategory { ringtone, calling, notification }

/// 同梱されている選択肢1件。表示名は`Strings`側（`settings_tab.dart`の
/// `soundPresetLabel`）で日英切り替えするため、ここでは持たない
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

extension SoundCategoryPresets on SoundCategory {
  /// このカテゴリで選べるプリセット一覧。
  ///
  /// 実際の音源ファイルの選定・確保は別途行う必要があるため、本番音源が
  /// 揃うまでの暫定措置として既存の`assets/sounds/`内3ファイルを使い回して
  /// いる（`call_ringtone.mp3`が「ユーザー提供のFLACをffmpeg変換した暫定
  /// 音源、後から差し替え可能な構成にした」だった前例と同じ運用、日記.md
  /// 参照）。本番音源が揃い次第、`assets/sounds/`へのファイル追加とこの
  /// 一覧の更新だけで差し替えられる（`pubspec.yaml`はディレクトリ単位で
  /// 宣言済みのため追加設定は不要）。
  List<SoundPreset> get presets => switch (this) {
    SoundCategory.ringtone => const [
      SoundPreset(
        id: 'ringtone_standard',
        assetPath: 'sounds/call_ringtone.mp3',
      ),
      SoundPreset(
        id: 'ringtone_soft',
        assetPath: 'sounds/participant_joined.mp3',
      ),
      SoundPreset(
        id: 'ringtone_simple',
        assetPath: 'sounds/participant_left.mp3',
      ),
    ],
    SoundCategory.calling => const [
      SoundPreset(
        id: 'calling_standard',
        assetPath: 'sounds/call_ringtone.mp3',
      ),
      SoundPreset(
        id: 'calling_soft',
        assetPath: 'sounds/participant_joined.mp3',
      ),
    ],
    SoundCategory.notification => const [
      SoundPreset(
        id: 'notification_standard',
        assetPath: 'sounds/call_ringtone.mp3',
      ),
      SoundPreset(
        id: 'notification_soft',
        assetPath: 'sounds/participant_joined.mp3',
      ),
      SoundPreset(
        id: 'notification_simple',
        assetPath: 'sounds/participant_left.mp3',
      ),
    ],
  };

  SoundPreset get defaultPreset => presets.first;

  /// 保存値（プリセットIDまたは`http`で始まるカスタムアップロード音源の
  /// ダウンロードURL）を、実際に再生できるソース文字列に解決する。
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
/// プリセットid>`）。チャンネルは作成後に音を変更できないため、音の
/// 選択肢ごとに別チャンネルを用意する方式にしている（`push_notifications.dart`・
/// `android_notification_sound_sync.dart`で共有、2026-09-06追加）。
String androidNotificationChannelIdFor(String presetId) =>
    'daidai_messages_$presetId';

/// カスタムアップロード通知音源用の固定チャンネルID。
const androidCustomNotificationChannelId = 'daidai_messages_custom';
