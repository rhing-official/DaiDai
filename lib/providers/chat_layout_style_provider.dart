import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_layout_style.dart';

const _prefsKey = 'chatLayoutStyle';

/// 端末に保存されている初期の語らい表示スタイル。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialChatLayoutStyleProvider = Provider<ChatLayoutStyle>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<ChatLayoutStyle> loadInitialChatLayoutStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return ChatLayoutStyle.fromName(prefs.getString(_prefsKey));
}

class ChatLayoutStyleNotifier extends Notifier<ChatLayoutStyle> {
  @override
  ChatLayoutStyle build() => ref.watch(initialChatLayoutStyleProvider);

  Future<void> setStyle(ChatLayoutStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final chatLayoutStyleProvider =
    NotifierProvider<ChatLayoutStyleNotifier, ChatLayoutStyle>(
  ChatLayoutStyleNotifier.new,
);
