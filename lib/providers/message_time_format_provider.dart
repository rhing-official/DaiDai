import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message_time_format.dart';
import 'repository_providers.dart';

const _prefsKey = 'messageTimeFormat';

/// 端末に保存されている初期のメッセージ時刻表示形式。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialMessageTimeFormatProvider = Provider<MessageTimeFormat>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<MessageTimeFormat> loadInitialMessageTimeFormat() async {
  final prefs = await SharedPreferences.getInstance();
  return MessageTimeFormat.fromName(prefs.getString(_prefsKey));
}

class MessageTimeFormatNotifier extends Notifier<MessageTimeFormat> {
  @override
  MessageTimeFormat build() => ref.watch(initialMessageTimeFormatProvider);

  Future<void> setFormat(MessageTimeFormat format) async {
    state = format;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, format.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'messageTimeFormat', format.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(MessageTimeFormat format) async {
    state = format;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, format.name);
  }
}

final messageTimeFormatProvider =
    NotifierProvider<MessageTimeFormatNotifier, MessageTimeFormat>(
      MessageTimeFormatNotifier.new,
    );
