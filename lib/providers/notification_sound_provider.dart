import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/android_notification_sound_sync.dart';
import 'repository_providers.dart';

const _prefsKey = 'notificationSound';

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
