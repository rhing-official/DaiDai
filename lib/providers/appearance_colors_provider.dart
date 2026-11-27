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

/// 胡粉（明るい背景）の、アクセント上の標準の色。純白。#EFEFF1は、明るい背景の上で、くすんだ
/// クリーム色に見えた（生成り、チョークで、選択中のアイコンが白く見えなかった、2026-11-27）。
/// 明るい背景の区分は、必ずこの色を標準にする（`test/appearance_colors_test.dart`が検査する）。
const kDefaultOnAccentColorLight = Color(0xFFFFFFFF);

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
    AppearanceColorKind.onAccent =>
      this == AppearanceSlot.light
          ? kDefaultOnAccentColorLight
          : kDefaultOnAccentColor,
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
    this.removedDefaults = const [],
  });

  /// 一覧から消した標準の色（全外観で共通。標準の色は外観ごとに違うので、色で持つ）。
  final List<Color> removedDefaults;

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
    List<Color>? removedDefaults,
  }) => KindColors(
    applied: applied == null ? this.applied : applied(),
    presets: presets ?? this.presets,
    defaultRemoved: defaultRemoved ?? this.defaultRemoved,
    removedDefaults: removedDefaults ?? this.removedDefaults,
  );

  Map<String, Object?> toJson() => {
    if (applied != null) 'applied': applied!.toARGB32(),
    'presets': [for (final c in presets) c.toARGB32()],
    'defaultRemoved': defaultRemoved,
    'removedDefaults': [for (final c in removedDefaults) c.toARGB32()],
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
      removedDefaults: json['removedDefaults'] is List
          ? [
              for (final p in json['removedDefaults'] as List)
                if (p is num) Color(p.toInt()),
            ]
          : const [],
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

/// 一覧の先頭に並ぶ標準の色。全外観の標準の色を、重複なく並べる。
List<Color> standardColorsOf(AppearanceColorKind kind) {
  final result = <Color>[];
  for (final s in AppearanceSlot.values) {
    final c = s.defaultFor(kind);
    if (!result.contains(c)) result.add(c);
  }
  return result;
}

/// 1つの外観の、1種類ぶんの色（表示・適用用）。フォントカラーもアクセント上も、プリセット（標準の色の削除を含む）を
/// 背景（外観）に関わらず共通にし、適用中の色だけを外観ごとに持つ。共通のプリセットは、
/// 胡粉の区分に保存する。以前に他の外観へ登録した色も、並びに足す。
KindColors kindColorsOf(
  AppearanceColors colors,
  AppearanceSlot slot,
  AppearanceColorKind kind,
) {
  final own = colors[slot]?[kind] ?? const KindColors();
  final shared = <Color>[];
  for (final s in [AppearanceSlot.light, ...AppearanceSlot.values]) {
    for (final c in colors[s]?[kind]?.presets ?? const <Color>[]) {
      if (!shared.contains(c) && shared.length < kMaxAppearancePresets) {
        shared.add(c);
      }
    }
  }
  // 消した標準の色。以前の保存（外観ごとの`defaultRemoved`）は、その外観の標準の色を消したものとして引き継ぐ。
  final removed = <Color>[];
  for (final s in AppearanceSlot.values) {
    final k = colors[s]?[kind];
    if (k == null) continue;
    for (final c in k.removedDefaults) {
      if (!removed.contains(c)) removed.add(c);
    }
    final legacy = s.defaultFor(kind);
    if (k.defaultRemoved && !removed.contains(legacy)) removed.add(legacy);
  }
  return KindColors(
    applied: own.applied,
    presets: shared,
    removedDefaults: removed,
  );
}

class AppearanceColorsNotifier extends Notifier<AppearanceColors> {
  @override
  AppearanceColors build() => ref.watch(initialAppearanceColorsProvider);

  KindColors of(AppearanceSlot slot, AppearanceColorKind kind) =>
      kindColorsOf(state, slot, kind);

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
    final changed = change(of(slot, kind));
    {
      // 適用中の色はこの外観にだけ、プリセットは全外観で共通（胡粉の区分）に保存する。
      final own = next[slot] ??= {};
      own[kind] = KindColors(applied: changed.applied);
      final shared = next[AppearanceSlot.light] ??= {};
      shared[kind] = KindColors(
        applied: shared[kind]?.applied,
        presets: changed.presets,
        removedDefaults: changed.removedDefaults,
      );
      if (slot == AppearanceSlot.light) {
        shared[kind] = shared[kind]!.copyWith(applied: () => changed.applied);
      }
      // 他の外観に残る古いプリセットは、共通へ寄せたので消す。
      for (final s in AppearanceSlot.values) {
        if (s == AppearanceSlot.light) continue;
        final k = next[s]?[kind];
        if (k != null) next[s]![kind] = KindColors(applied: k.applied);
      }
    }
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
    final alreadyShown =
        (standardColorsOf(kind).contains(c) &&
            !current.removedDefaults.contains(c)) ||
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

  /// 標準の色の1つを一覧から削除する（適用中の色はそのまま。全外観で共通）。
  Future<void> removeDefault(
    AppearanceSlot slot,
    AppearanceColorKind kind,
    Color color,
  ) => _update(
    slot,
    kind,
    (k) => k.copyWith(removedDefaults: [...k.removedDefaults, color]),
  );

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
