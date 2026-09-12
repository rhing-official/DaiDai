import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_sound_upload.dart';
import 'repository_providers.dart';

const _prefsKey = 'callingSound';
const _customUrlPrefsKey = 'callingSoundCustomUrl';
const _customFileNamePrefsKey = 'callingSoundCustomFileName';

/// 端末に保存されている初期の呼出音設定（プリセットIDまたはカスタム
/// アップロード音源のURL、未設定ならnull＝既定プリセット）。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （`ringtone_sound_provider.dart`と同じパターン、2026-09-06追加）。
final initialCallingSoundProvider = Provider<String?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<String?> loadInitialCallingSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

/// 端末に保存されている、最後にアップロードしたカスタム呼出音（URL＋
/// 元ファイル名）。プリセットに切り替えたあとも保持し続ける（2026-09-12
/// 追加、`ringtone_sound_provider.dart`の`initialRingtoneCustomSoundProvider`
/// と同じ理由・同じパターン）。この端末のみの記憶でFirestoreへは同期しない。
final initialCallingCustomSoundProvider = Provider<CustomSoundUpload?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<CustomSoundUpload?> loadInitialCallingCustomSound() async {
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString(_customUrlPrefsKey);
  if (url == null) return null;
  return CustomSoundUpload(
    url: url,
    fileName: prefs.getString(_customFileNamePrefsKey),
  );
}

class CallingSoundNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialCallingSoundProvider);

  Future<void> setSound(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'callingSound', value);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
  }
}

final callingSoundProvider = NotifierProvider<CallingSoundNotifier, String?>(
  CallingSoundNotifier.new,
);

class CallingCustomSoundNotifier extends Notifier<CustomSoundUpload?> {
  @override
  CustomSoundUpload? build() => ref.watch(initialCallingCustomSoundProvider);

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

final callingCustomSoundProvider =
    NotifierProvider<CallingCustomSoundNotifier, CustomSoundUpload?>(
      CallingCustomSoundNotifier.new,
    );
