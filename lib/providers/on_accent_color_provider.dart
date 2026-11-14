import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

/// 旧版（ライト/ダーク共通の1色、0は自動）の保存キー。読み出しの移行にだけ使う。
const _legacyPrefsKey = 'onAccentColorArgb32';

/// 未設定の時の既定の文字色（2026-11-14、ライト用は黒・ダーク用は白）。以前は未設定を
/// 「自動」（空欄）としていたが、見た目は同じ値のため、文字色（ライト用・ダーク用）と同じく
/// 最初から実際の色として持つ。
const kDefaultOnAccentColorLight = Colors.black;
const kDefaultOnAccentColorDark = Colors.white;

/// アクセントカラーで塗った面（選択中のチップ・ボタン・ピルなど）の上に乗る文字・
/// アイコンの色（2026-11-06追加）。2026-11-14に、文字色（`text_color_provider.dart`）と同じく
/// ライト用・ダーク用の2色に分けた。常に不透明として扱う。
class _OnAccentColorNotifier extends Notifier<Color> {
  _OnAccentColorNotifier({
    required this.prefsKey,
    required this.remoteField,
    required this.defaultColor,
  });

  final String prefsKey;
  final String remoteField;
  final Color defaultColor;

  @override
  Color build() {
    _load();
    return defaultColor;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getInt(prefsKey);
    // 旧版の1色を、ライト用・ダーク用の両方に引き継ぐ。
    if (value == null) {
      final legacy = prefs.getInt(_legacyPrefsKey);
      if (legacy != null && legacy != 0) value = legacy;
    }
    if (value != null) state = Color(value).withAlpha(0xFF);
  }

  Future<void> setColor(Color color) async {
    final opaque = color.withAlpha(0xFF);
    state = opaque;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, opaque.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, remoteField, opaque.toARGB32());
  }

  /// ログイン時、Firestoreの値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(int value) async {
    state = Color(value).withAlpha(0xFF);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, state.toARGB32());
  }
}

class OnAccentColorLightNotifier extends _OnAccentColorNotifier {
  OnAccentColorLightNotifier()
    : super(
        prefsKey: 'onAccentColorLightArgb32',
        remoteField: 'onAccentColorLightArgb',
        defaultColor: kDefaultOnAccentColorLight,
      );
}

class OnAccentColorDarkNotifier extends _OnAccentColorNotifier {
  OnAccentColorDarkNotifier()
    : super(
        prefsKey: 'onAccentColorDarkArgb32',
        remoteField: 'onAccentColorDarkArgb',
        defaultColor: kDefaultOnAccentColorDark,
      );
}

final onAccentColorLightProvider =
    NotifierProvider<OnAccentColorLightNotifier, Color>(
      OnAccentColorLightNotifier.new,
    );

final onAccentColorDarkProvider =
    NotifierProvider<OnAccentColorDarkNotifier, Color>(
      OnAccentColorDarkNotifier.new,
    );
