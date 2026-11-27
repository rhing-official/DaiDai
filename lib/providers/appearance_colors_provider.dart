import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dark_variant.dart';
import 'custom_appearance_provider.dart';
import 'dark_variant_provider.dart';
import 'repository_providers.dart';
import 'theme_mode_provider.dart';

const _prefsKey = 'appearanceColors';

/// 外観ごとの、フォントカラー・アクセント上の色の既定（2026-11-18）。胡粉（ライト）の文字色。
/// ダークは[DarkVariant.defaultTextColor]。アクセント上は4つの外観すべて共通。
const kDefaultTextColorLight = Color(0xFF71727B);
const kDefaultOnAccentColor = Color(0xFFEFEFF1);

/// 外観ごとに登録できるプリセット（標準の色とは別に、自分で登録する数）の上限。
const kMaxAppearancePresets = 3;

/// 外観（胡粉・墨・鈍色・漆黒）の区分。ライト=胡粉、ダークは[DarkVariant]に対応する。
enum AppearanceSlot {
  light,
  standard,
  soft,
  black;

  static AppearanceSlot of(ThemeMode mode, DarkVariant variant) {
    if (mode != ThemeMode.dark) return AppearanceSlot.light;
    return switch (variant) {
      DarkVariant.standard => AppearanceSlot.standard,
      DarkVariant.soft => AppearanceSlot.soft,
      DarkVariant.black => AppearanceSlot.black,
    };
  }

  Color defaultFor(AppearanceColorKind kind) => switch (kind) {
    AppearanceColorKind.text => switch (this) {
      AppearanceSlot.light => kDefaultTextColorLight,
      AppearanceSlot.standard => DarkVariant.standard.defaultTextColor,
      AppearanceSlot.soft => DarkVariant.soft.defaultTextColor,
      AppearanceSlot.black => DarkVariant.black.defaultTextColor,
    },
    AppearanceColorKind.onAccent => kDefaultOnAccentColor,
  };
}

/// 色の種類。フォントカラー（主な文字）とアクセント上（アクセントで塗った面の上の文字）。
enum AppearanceColorKind { text, onAccent }

/// 1つの外観での、1種類ぶんの色の設定。
class KindColors {
  const KindColors({
    this.applied,
    this.presets = const [],
    this.defaultRemoved = false,
  });

  /// 適用中の色（null=標準の色）。
  final Color? applied;

  /// 自分で登録したプリセット（最大[kMaxAppearancePresets]）。
  final List<Color> presets;

  /// 最初のプリセット（標準の色）を削除したか。
  final bool defaultRemoved;

  KindColors copyWith({
    Color? Function()? applied,
    List<Color>? presets,
    bool? defaultRemoved,
  }) => KindColors(
    applied: applied == null ? this.applied : applied(),
    presets: presets ?? this.presets,
    defaultRemoved: defaultRemoved ?? this.defaultRemoved,
  );

  Map<String, Object?> toJson() => {
    if (applied != null) 'applied': applied!.toARGB32(),
    'presets': [for (final c in presets) c.toARGB32()],
    'defaultRemoved': defaultRemoved,
  };

  static KindColors fromJson(Object? json) {
    if (json is! Map) return const KindColors();
    final applied = json['applied'];
    final presets = json['presets'];
    return KindColors(
      applied: applied is num ? Color(applied.toInt()) : null,
      presets: presets is List
          ? [
              for (final p in presets)
                if (p is num) Color(p.toInt()),
            ].take(kMaxAppearancePresets).toList()
          : const [],
      defaultRemoved: json['defaultRemoved'] == true,
    );
  }
}

/// 外観の区分ごとの全設定。
typedef AppearanceColors =
    Map<AppearanceSlot, Map<AppearanceColorKind, KindColors>>;

Map<String, Object?> appearanceColorsToJson(AppearanceColors colors) => {
  for (final slot in colors.keys)
    slot.name: {
      for (final kind in colors[slot]!.keys)
        kind.name: colors[slot]![kind]!.toJson(),
    },
};

AppearanceColors appearanceColorsFromJson(Object? json) {
  final result = <AppearanceSlot, Map<AppearanceColorKind, KindColors>>{};
  if (json is! Map) return result;
  for (final slot in AppearanceSlot.values) {
    final slotJson = json[slot.name];
    if (slotJson is! Map) continue;
    result[slot] = {
      for (final kind in AppearanceColorKind.values)
        kind: KindColors.fromJson(slotJson[kind.name]),
    };
  }
  return result;
}

/// 端末に保存されている初期値。main()で起動前に読み込んでoverrideする（未指定は空＝全て既定）。
final initialAppearanceColorsProvider = Provider<AppearanceColors>((ref) => {});

Future<AppearanceColors> loadInitialAppearanceColors() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefsKey);
  if (raw == null) return {};
  try {
    return appearanceColorsFromJson(jsonDecode(raw));
  } catch (_) {
    return {};
  }
}

class AppearanceColorsNotifier extends Notifier<AppearanceColors> {
  @override
  AppearanceColors build() => ref.watch(initialAppearanceColorsProvider);

  KindColors of(AppearanceSlot slot, AppearanceColorKind kind) =>
      state[slot]?[kind] ?? const KindColors();

  /// アクセント上は常に不透明にする。
  Color _normalize(AppearanceColorKind kind, Color color) =>
      kind == AppearanceColorKind.onAccent ? color.withAlpha(0xFF) : color;

  Future<void> _update(
    AppearanceSlot slot,
    AppearanceColorKind kind,
    KindColors Function(KindColors) change,
  ) async {
    final next = {
      for (final e in state.entries) e.key: {...e.value},
    };
    final slotMap = next[slot] ??= {};
    slotMap[kind] = change(of(slot, kind));
    state = next;
    final json = appearanceColorsToJson(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(json));
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'appearanceColors', json);
  }

  /// 色を適用する（その外観にだけ保存される）。
  Future<void> apply(
    AppearanceSlot slot,
    AppearanceColorKind kind,
    Color color,
  ) => _update(
    slot,
    kind,
    (k) => k.copyWith(applied: () => _normalize(kind, color)),
  );

  /// 色をプリセットへ登録する。既に一覧にある・上限に達している時は何もせず`false`。
  Future<bool> addPreset(
    AppearanceSlot slot,
    AppearanceColorKind kind,
    Color color,
  ) async {
    final c = _normalize(kind, color);
    final current = of(slot, kind);
    final standard = slot.defaultFor(kind);
    final alreadyShown =
        (!current.defaultRemoved && standard == c) ||
        current.presets.contains(c);
    if (alreadyShown) return true;
    if (current.presets.length >= kMaxAppearancePresets) return false;
    await _update(slot, kind, (k) => k.copyWith(presets: [...k.presets, c]));
    return true;
  }

  Future<void> removePreset(
    AppearanceSlot slot,
    AppearanceColorKind kind,
    Color color,
  ) => _update(
    slot,
    kind,
    (k) => k.copyWith(presets: k.presets.where((p) => p != color).toList()),
  );

  /// 最初のプリセット（標準の色）を削除する（適用中の色はそのまま）。
  Future<void> removeDefault(AppearanceSlot slot, AppearanceColorKind kind) =>
      _update(slot, kind, (k) => k.copyWith(defaultRemoved: true));

  /// ログイン時、アカウントに保存されている値で端末側を上書きする（書き戻しはしない）。
  Future<void> syncFromRemote(AppearanceColors colors) async {
    state = colors;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(appearanceColorsToJson(colors)),
    );
  }
}

final appearanceColorsProvider =
    NotifierProvider<AppearanceColorsNotifier, AppearanceColors>(
      AppearanceColorsNotifier.new,
    );

/// 今の外観の区分（テーマの明暗とダークの種類から決まる）。
///
/// カスタムの外観の間は、背景色の明るさで画面のライト/ダークが決まる（`main.dart`）ので、
/// ライト/ダークの選択ではなく背景色の明るさに合わせる。合わせないと、端末がダークの時に
/// 明るい背景を決めても、設定した色がダークの区分に保存され、ライトの画面に反映されない。
final currentAppearanceSlotProvider = Provider<AppearanceSlot>((ref) {
  final custom = ref.watch(customAppearanceProvider);
  final mode = custom.enabled
      ? (ThemeData.estimateBrightnessForColor(custom.color) == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light)
      : ref.watch(appThemeModeProvider);
  return AppearanceSlot.of(mode, ref.watch(darkVariantProvider));
});

/// 実際に使う色（適用中 ?? その外観の標準の色）。
final effectiveAppearanceColorProvider =
    Provider.family<Color, (AppearanceSlot, AppearanceColorKind)>((ref, key) {
      final (slot, kind) = key;
      final kindColors = ref.watch(
        appearanceColorsProvider.select((s) => s[slot]?[kind]),
      );
      return kindColors?.applied ?? slot.defaultFor(kind);
    });

/// ライトテーマ・ダークテーマに渡す色（`main.dart`用）。ダークは今選んでいる種類の色。
final effectiveTextColorLightProvider = Provider<Color>(
  (ref) => ref.watch(
    effectiveAppearanceColorProvider((
      AppearanceSlot.light,
      AppearanceColorKind.text,
    )),
  ),
);

final effectiveTextColorDarkProvider = Provider<Color>((ref) {
  final slot = AppearanceSlot.of(
    ThemeMode.dark,
    ref.watch(darkVariantProvider),
  );
  return ref.watch(
    effectiveAppearanceColorProvider((slot, AppearanceColorKind.text)),
  );
});

final effectiveOnAccentColorLightProvider = Provider<Color>(
  (ref) => ref.watch(
    effectiveAppearanceColorProvider((
      AppearanceSlot.light,
      AppearanceColorKind.onAccent,
    )),
  ),
);

final effectiveOnAccentColorDarkProvider = Provider<Color>((ref) {
  final slot = AppearanceSlot.of(
    ThemeMode.dark,
    ref.watch(darkVariantProvider),
  );
  return ref.watch(
    effectiveAppearanceColorProvider((slot, AppearanceColorKind.onAccent)),
  );
});
