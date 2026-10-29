import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'recentStickerIds';

/// 最近使ったぺったんの保持件数。
const kRecentStickerLimit = 30;

/// 先頭に[stickerId]を足した最近使ったぺったんのid列（重複は先頭へ移動、
/// 上限は[kRecentStickerLimit]）。
List<String> addRecentSticker(List<String> current, String stickerId) => [
  stickerId,
  ...current.where((id) => id != stickerId),
].take(kRecentStickerLimit).toList();

/// 最近使ったぺったんのid（新しい順、2026-10-29追加）。端末ごとの
/// `SharedPreferences`保存で、Firestoreには同期しない（別端末へは引き継がない）。
/// 起動時の読み込みは非同期で、読み込み前は空。
class RecentStickersNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    // 読み込み中に記録された分を優先して、後ろへ保存済みを足す。
    if (saved == null) return;
    var merged = saved;
    for (final id in state.reversed) {
      merged = addRecentSticker(merged, id);
    }
    state = merged;
  }

  Future<void> record(String stickerId) async {
    state = addRecentSticker(state, stickerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
  }
}

final recentStickersProvider =
    NotifierProvider<RecentStickersNotifier, List<String>>(
      RecentStickersNotifier.new,
    );
