import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_navigation_providers.dart';

const _prefsKey = 'lastOpenedRoomByConversation';

/// [ViewedConversation]をSharedPreferences保存用の文字列キーに変換する
/// （2026-09-26追加）。`dm:`/`group:`のprefixで一対/広場のid空間の衝突を防ぐ。
String _keyFor(ViewedConversation conversation) => switch (conversation) {
  ViewedDm(:final dmId) => 'dm:$dmId',
  ViewedGroup(:final groupId) => 'group:$groupId',
};

/// [LastOpenedRoomNotifier]の状態（[lastOpenedRoomProvider]の値）から
/// [conversation]の最後に開いた寄合idを引く。`ref.watch(...select)`で
/// リアクティブに読むために公開している（2026-10-06追加）。
String? lastOpenedRoomIn(
  Map<String, String> state,
  ViewedConversation conversation,
) => state[_keyFor(conversation)];

/// 端末に保存されている、会話ごとに最後に開いていた寄合idの初期値。main()で
/// 起動前に読み込み、ProviderScopeのoverrideとして渡す（[AccentColorNotifier]
/// と同じ方式）。
final initialLastOpenedRoomsProvider = Provider<Map<String, String>>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Map<String, String>> loadInitialLastOpenedRooms() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null) return const {};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value as String));
}

/// 会話（一対/広場）ごとに、最後に表示していた寄合のidを記憶する
/// （2026-09-26追加）。以前は寄合一覧・アイコンタップからの遷移先が常に
/// 先頭（最古）の寄合へ決め打ちされており、メッセージ画面で別の寄合へ切り
/// 替えても語らい一覧に戻ると忘れられてしまっていた。書き込みは
/// `DmChatPane`/`GroupChatPane`（`initState`・`_switchRoom`）に一本化して
/// おり、どの経路で寄合を開いても必ずここを通る。読み込み側は
/// `talks_tab.dart`のアイコンタップ・寄合一覧のフォールバック解決で使う。
class LastOpenedRoomNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => ref.watch(initialLastOpenedRoomsProvider);

  String? lastRoomFor(ViewedConversation conversation) =>
      state[_keyFor(conversation)];

  Future<void> setLastRoom(
    ViewedConversation conversation,
    String roomId,
  ) async {
    // `DmChatPane`/`GroupChatPane`の`initState`（ウィジェット構築中）からも
    // 呼ばれるため、次のマイクロタスクまで待ってからstateを更新する
    // （2026-10-06修正。構築中のプロバイダ変更はRiverpodが例外
    // 「Tried to modify a provider while the widget tree was building」を
    // 投げ、初回表示時の「最後に開いた寄合」の記録が丸ごと失敗していた）。
    await Future<void>.value();
    final key = _keyFor(conversation);
    if (state[key] == roomId) return;
    state = {...state, key: roomId};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state));
  }
}

final lastOpenedRoomProvider =
    NotifierProvider<LastOpenedRoomNotifier, Map<String, String>>(
      LastOpenedRoomNotifier.new,
    );
