import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/text_prominence_colors.dart';
import 'repository_providers.dart';

const _lightPrefsKey = 'textColorLightArgb32';
const _darkPrefsKey = 'textColorDarkArgb32';

/// ユーザーが未設定の場合に使う既定の文字色（`accentColorProvider`と同じ
/// パターン、2026-09-14追加）。`TextProminence`の既存の固定値と同じにして
/// あるため、未設定の間は見た目が変わらない。
const kDefaultTextColorLight = TextProminence.lightPrimary;
const kDefaultTextColorDark = TextProminence.darkPrimary;

final initialTextColorLightProvider = Provider<Color>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

final initialTextColorDarkProvider = Provider<Color>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<Color> loadInitialTextColorLight() async {
  final prefs = await SharedPreferences.getInstance();
  final argb32 = prefs.getInt(_lightPrefsKey);
  return argb32 == null ? kDefaultTextColorLight : Color(argb32);
}

Future<Color> loadInitialTextColorDark() async {
  final prefs = await SharedPreferences.getInstance();
  final argb32 = prefs.getInt(_darkPrefsKey);
  return argb32 == null ? kDefaultTextColorDark : Color(argb32);
}

/// ライト/ダークそれぞれの文字色（`colorScheme.onSurface`相当）を
/// ユーザーがカラーコードで指定できるようにする（2026-09-14追加）。
/// アクセントカラーと異なり背景とのコントラストが直接文字の可読性に
/// 関わるため、ライト・ダークで別々の色を保存する
/// （`accentColorProvider`が1色をライト/ダーク共通で使うのとは異なる方針、
/// ユーザー確認済み）。
class _TextColorNotifier extends Notifier<Color> {
  _TextColorNotifier({
    required this.initialProvider,
    required this.prefsKey,
    required this.remoteField,
  });

  final Provider<Color> initialProvider;
  final String prefsKey;
  final String remoteField;

  @override
  Color build() => ref.watch(initialProvider);

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, color.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, remoteField, color.toARGB32());
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, color.toARGB32());
  }
}

class TextColorLightNotifier extends _TextColorNotifier {
  TextColorLightNotifier()
    : super(
        initialProvider: initialTextColorLightProvider,
        prefsKey: _lightPrefsKey,
        remoteField: 'textColorLightArgb',
      );
}

class TextColorDarkNotifier extends _TextColorNotifier {
  TextColorDarkNotifier()
    : super(
        initialProvider: initialTextColorDarkProvider,
        prefsKey: _darkPrefsKey,
        remoteField: 'textColorDarkArgb',
      );
}

final textColorLightProvider = NotifierProvider<TextColorLightNotifier, Color>(
  TextColorLightNotifier.new,
);

final textColorDarkProvider = NotifierProvider<TextColorDarkNotifier, Color>(
  TextColorDarkNotifier.new,
);
