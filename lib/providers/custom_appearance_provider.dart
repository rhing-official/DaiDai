import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _enabledKey = 'customAppearanceEnabled';
const _colorKey = 'customAppearanceColor';

/// カスタムの外観の初期の背景色（鈍色に近い暗い色）。
const Color kDefaultCustomAppearanceColor = Color(0xFF23232B);

/// カスタムの外観（2026-11-26）。外観の5つ目で、背景色をカラーコードで決める。[enabled]が
/// `true`の間は、ライト/ダークの選択に代わって、背景色の明るさで、ライトかダークが決まる。
@immutable
class CustomAppearance {
  const CustomAppearance({
    this.enabled = false,
    this.color = kDefaultCustomAppearanceColor,
  });

  final bool enabled;
  final Color color;

  CustomAppearance copyWith({bool? enabled, Color? color}) => CustomAppearance(
    enabled: enabled ?? this.enabled,
    color: color ?? this.color,
  );
}

/// 端末に保存されている初期値。`main()`で起動前に読み込んで渡す（未指定のテストでは無効）。
final initialCustomAppearanceProvider = Provider<CustomAppearance>(
  (ref) => const CustomAppearance(),
);

Future<CustomAppearance> loadInitialCustomAppearance() async {
  final prefs = await SharedPreferences.getInstance();
  final argb = prefs.getInt(_colorKey);
  return CustomAppearance(
    enabled: prefs.getBool(_enabledKey) ?? false,
    color: argb == null ? kDefaultCustomAppearanceColor : Color(argb),
  );
}

class CustomAppearanceNotifier extends Notifier<CustomAppearance> {
  @override
  CustomAppearance build() => ref.watch(initialCustomAppearanceProvider);

  Future<void> _save(CustomAppearance next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, next.enabled);
    await prefs.setInt(_colorKey, next.color.toARGB32());
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    final repo = ref.read(userRepositoryProvider);
    await repo.updateUserPreference(
      userId,
      'customAppearanceEnabled',
      next.enabled,
    );
    await repo.updateUserPreference(
      userId,
      'customAppearanceColor',
      next.color.toARGB32(),
    );
  }

  Future<void> setEnabled(bool enabled) =>
      _save(state.copyWith(enabled: enabled));

  /// 背景色を決める。同時に、カスタムの外観を有効にする。
  Future<void> setColor(Color color) =>
      _save(state.copyWith(enabled: true, color: color.withAlpha(0xFF)));

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote({bool? enabled, int? color}) async {
    state = state.copyWith(
      enabled: enabled,
      color: color == null ? null : Color(color),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, state.enabled);
    await prefs.setInt(_colorKey, state.color.toARGB32());
  }
}

final customAppearanceProvider =
    NotifierProvider<CustomAppearanceNotifier, CustomAppearance>(
      CustomAppearanceNotifier.new,
    );
