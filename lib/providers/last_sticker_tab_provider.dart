import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'lastStickerTabByRoom';

/// 記憶する語らい（寄合）の最大件数。超えたら古いものから落とす。
const kLastStickerTabLimit = 200;

/// ぺったん一覧で、タブが「最近使った」「すべて」を表す値（パックidと
/// 衝突しない）。
const kStickerTabRecent = '__recent__';
const kStickerTabAll = '__all__';

/// 語らいごとの記憶のキー。寄合があれば`会話/寄合`、無ければ会話。どちらも
/// 無ければnull（記憶しない）。
String? stickerTabKey({String? conversationId, String? roomId}) {
  if (conversationId == null) return null;
  return roomId == null ? conversationId : '$conversationId/$roomId';
}

/// [key]のタブを[tab]へ更新した新しい記憶（更新したものを末尾＝最新にし、
/// 上限を超えたら先頭＝古いものから落とす）。
Map<String, String> rememberTab(
  Map<String, String> current,
  String key,
  String tab,
) {
  final next = Map<String, String>.of(current)
    ..remove(key)
    ..[key] = tab;
  while (next.length > kLastStickerTabLimit) {
    next.remove(next.keys.first);
  }
  return next;
}

/// 語らいごとに直前に開いていたぺったん一覧のタブ（2026-10-30追加）。
/// 端末ごとの`SharedPreferences`保存で、Firestoreには同期しない。起動時の
/// 読み込みは非同期で、読み込み前は空。
class LastStickerTabNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final saved = (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );
      // 読み込み中に記録された分を優先する。
      state = {...saved, ...state};
    } catch (_) {
      // 壊れた保存値は無視する。
    }
  }

  Future<void> remember(String key, String tab) async {
    state = rememberTab(state, key, tab);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state));
  }
}

final lastStickerTabProvider =
    NotifierProvider<LastStickerTabNotifier, Map<String, String>>(
      LastStickerTabNotifier.new,
    );
