import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 設定の中の折りたたみ（詳細設定・フォントデザインの「もっと見る」・ブロックした
/// ユーザーの「もっと見る」など）の開閉を、別のカテゴリへ移って戻っても保つ（2026-11-06）。
/// アプリを動かしている間だけ覚える（端末へは保存しない）。キーは項目ごとの固定の名前。
class SettingsExpansionNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String key, bool expanded) {
    state = {...state, key: expanded};
  }
}

final settingsExpansionProvider =
    NotifierProvider<SettingsExpansionNotifier, Map<String, bool>>(
      SettingsExpansionNotifier.new,
    );

/// 項目[key]の開閉。未操作なら[initial]。
extension SettingsExpansionRead on Map<String, bool> {
  bool expandedOr(String key, bool initial) => this[key] ?? initial;
}
