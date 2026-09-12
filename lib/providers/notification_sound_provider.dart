import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_sound_upload.dart';
import '../utils/android_notification_sound_sync.dart';
import 'repository_providers.dart';

const _prefsKey = 'notificationSound';
const _customUrlPrefsKey = 'notificationSoundCustomUrl';
const _customFileNamePrefsKey = 'notificationSoundCustomFileName';

/// 端末に保存されている初期の通知音設定（プリセットIDまたはカスタム
/// アップロード音源のURL、未設定ならnull＝既定プリセット）。Androidのみ
/// 対応（`SoundCategory.notification`参照、2026-09-06 Phase B追加）。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （`ringtone_sound_provider.dart`と同じパターン）。
final initialNotificationSoundProvider = Provider<String?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<String?> loadInitialNotificationSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

/// 端末に保存されている、最後にアップロードしたカスタム通知音（URL＋
/// 元ファイル名）。プリセットに切り替えたあとも保持し続ける（2026-09-12
/// 追加、`ringtone_sound_provider.dart`の
/// `initialRingtoneCustomSoundProvider`と同じ理由・同じパターン）。この
/// 端末のみの記憶でFirestoreへは同期しない。
final initialNotificationCustomSoundProvider = Provider<CustomSoundUpload?>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<CustomSoundUpload?> loadInitialNotificationCustomSound() async {
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString(_customUrlPrefsKey);
  if (url == null) return null;
  return CustomSoundUpload(
    url: url,
    fileName: prefs.getString(_customFileNamePrefsKey),
  );
}

class NotificationSoundNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialNotificationSoundProvider);

  Future<void> setSound(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    if (value.startsWith('http')) {
      unawaited(ensureCustomNotificationChannelReady(value));
    }
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'notificationSound', value);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。他端末で既に
  /// アップロード済みのカスタム音源が同期されてきた場合、この端末でも
  /// ダウンロード・チャンネル作成を行う。
  Future<void> syncFromRemote(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    if (value.startsWith('http')) {
      unawaited(ensureCustomNotificationChannelReady(value));
    }
  }
}

final notificationSoundProvider =
    NotifierProvider<NotificationSoundNotifier, String?>(
      NotificationSoundNotifier.new,
    );

class NotificationCustomSoundNotifier extends Notifier<CustomSoundUpload?> {
  @override
  CustomSoundUpload? build() =>
      ref.watch(initialNotificationCustomSoundProvider);

  /// カスタム音源をアップロードした際、または既に有効なカスタム音源を
  /// この記憶がまだ無い状態で選び直した際（バックフィル、`fileName`は
  /// 不明なのでnull）に呼ぶ。プリセットに切り替えてもこの記憶はクリア
  /// されない（設定画面の「アップロード」行本体タップで再アップロード
  /// せずに呼び戻せるようにするため）。
  Future<void> remember(String url, [String? fileName]) async {
    state = CustomSoundUpload(url: url, fileName: fileName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customUrlPrefsKey, url);
    if (fileName == null) {
      await prefs.remove(_customFileNamePrefsKey);
    } else {
      await prefs.setString(_customFileNamePrefsKey, fileName);
    }
  }
}

final notificationCustomSoundProvider =
    NotifierProvider<NotificationCustomSoundNotifier, CustomSoundUpload?>(
      NotificationCustomSoundNotifier.new,
    );
