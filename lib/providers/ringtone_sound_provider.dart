import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_sound_upload.dart';
import 'repository_providers.dart';

const _prefsKey = 'ringtoneSound';
const _customUrlPrefsKey = 'ringtoneSoundCustomUrl';
const _customFileNamePrefsKey = 'ringtoneSoundCustomFileName';

/// 端末に保存されている初期の着信音設定（プリセットIDまたはカスタム
/// アップロード音源のURL、未設定ならnull＝既定プリセット）。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す
/// （`font_design_provider.dart`と同じパターン、2026-09-06追加）。
final initialRingtoneSoundProvider = Provider<String?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<String?> loadInitialRingtoneSound() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

/// 端末に保存されている、最後にアップロードしたカスタム着信音（URL＋
/// 元ファイル名）。プリセットに切り替えたあとも保持し続ける（2026-09-12
/// 追加、設定画面で「アップロード」を選び直すたびに再アップロードを
/// 求められる問題への対応）。この端末のみの記憶でFirestoreへは同期しない。
final initialRingtoneCustomSoundProvider = Provider<CustomSoundUpload?>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<CustomSoundUpload?> loadInitialRingtoneCustomSound() async {
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString(_customUrlPrefsKey);
  if (url == null) return null;
  return CustomSoundUpload(
    url: url,
    fileName: prefs.getString(_customFileNamePrefsKey),
  );
}

class RingtoneSoundNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialRingtoneSoundProvider);

  Future<void> setSound(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'ringtoneSound', value);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
  }
}

final ringtoneSoundProvider = NotifierProvider<RingtoneSoundNotifier, String?>(
  RingtoneSoundNotifier.new,
);

class RingtoneCustomSoundNotifier extends Notifier<CustomSoundUpload?> {
  @override
  CustomSoundUpload? build() => ref.watch(initialRingtoneCustomSoundProvider);

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

final ringtoneCustomSoundProvider =
    NotifierProvider<RingtoneCustomSoundNotifier, CustomSoundUpload?>(
      RingtoneCustomSoundNotifier.new,
    );
