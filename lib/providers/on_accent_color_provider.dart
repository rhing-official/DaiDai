import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'onAccentColorArgb32';

/// 「自動」（未設定）を表す保存値。クライアントとFirestoreの両方でこの値を使う
/// （Firestoreにはフィールドの削除ではなく0を書く）。
const _autoValue = 0;

/// アクセントカラーで塗った面（選択中のチップ・ボタン・ピルなど）の上に乗る文字・
/// アイコンの色（2026-11-06追加）。nullなら自動（ライトは黒・ダークは白、従来通り）。
/// アクセントが背景になり外観に左右されない為、ライト/ダーク共通の1色。
/// 常に不透明として扱う。
class OnAccentColorNotifier extends Notifier<Color?> {
  @override
  Color? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefsKey);
    if (value != null && value != _autoValue) {
      state = Color(value).withAlpha(0xFF);
    }
  }

  Future<void> setColor(Color? color) async {
    final opaque = color?.withAlpha(0xFF);
    state = opaque;
    final value = opaque?.toARGB32() ?? _autoValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'onAccentColorArgb', value);
  }

  /// ログイン時、Firestoreの値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(int value) async {
    state = value == _autoValue ? null : Color(value).withAlpha(0xFF);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }
}

final onAccentColorProvider = NotifierProvider<OnAccentColorNotifier, Color?>(
  OnAccentColorNotifier.new,
);
