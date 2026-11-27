import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/models/dark_variant.dart';
import 'package:daidai/providers/appearance_colors_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  const text = AppearanceColorKind.text;
  const onAccent = AppearanceColorKind.onAccent;

  test('既定は外観ごとの標準の色', () {
    final c = make();
    Color eff(AppearanceSlot s, AppearanceColorKind k) =>
        c.read(effectiveAppearanceColorProvider((s, k)));
    expect(eff(AppearanceSlot.light, text), const Color(0xFF71727B));
    expect(eff(AppearanceSlot.standard, text), const Color(0xFFD5D5D5));
    expect(eff(AppearanceSlot.soft, text), const Color(0xFFD5D5D5));
    expect(eff(AppearanceSlot.black, text), const Color(0xFFD5D5D5));
    // 明るい背景（胡粉）は純白。#EFEFF1は、明るい背景でクリーム色に見えた。
    expect(eff(AppearanceSlot.light, onAccent), const Color(0xFFFFFFFF));
    for (final s in AppearanceSlot.values.where(
      (s) => s != AppearanceSlot.light,
    )) {
      expect(eff(s, onAccent), const Color(0xFFEFEFF1));
    }
  });

  test('適用した色は、その外観にだけ保存される', () async {
    final c = make();
    final n = c.read(appearanceColorsProvider.notifier);
    await n.apply(AppearanceSlot.soft, text, const Color(0xFF112233));
    expect(
      c.read(effectiveAppearanceColorProvider((AppearanceSlot.soft, text))),
      const Color(0xFF112233),
    );
    expect(
      c.read(effectiveAppearanceColorProvider((AppearanceSlot.black, text))),
      const Color(0xFFD5D5D5),
    );
    // アクセント上は常に不透明。
    await n.apply(AppearanceSlot.light, onAccent, const Color(0x80112233));
    expect(
      c.read(
        effectiveAppearanceColorProvider((AppearanceSlot.light, onAccent)),
      ),
      const Color(0xFF112233),
    );
  });

  test('プリセットは全外観で共通で最大3つ、重複と標準の色は増えない', () async {
    final c = make();
    final n = c.read(appearanceColorsProvider.notifier);
    const slot = AppearanceSlot.standard;
    expect(await n.addPreset(slot, text, const Color(0xFFD5D5D5)), isTrue);
    expect(n.of(slot, text).presets, isEmpty); // 標準の色と同じ
    for (final v in [1, 2, 3]) {
      expect(await n.addPreset(slot, text, Color(0xFF000000 + v)), isTrue);
    }
    expect(await n.addPreset(slot, text, const Color(0xFF000004)), isFalse);
    expect(n.of(slot, text).presets.length, kMaxAppearancePresets);
    // 別の外観にも、同じ一覧が出る。別の種類には影響しない。
    expect(n.of(AppearanceSlot.black, text).presets.length, 3);
    expect(n.of(slot, onAccent).presets, isEmpty);
  });

  test('プリセットと標準の色を削除できる（適用中の色は変わらない）', () async {
    final c = make();
    final n = c.read(appearanceColorsProvider.notifier);
    const slot = AppearanceSlot.light;
    await n.addPreset(slot, text, const Color(0xFF123456));
    await n.removePreset(slot, text, const Color(0xFF123456));
    expect(n.of(slot, text).presets, isEmpty);
    await n.removeDefault(slot, text, const Color(0xFF71727B));
    expect(n.of(slot, text).removedDefaults, [const Color(0xFF71727B)]);
    // 標準の色の削除は、全外観で共通。
    expect(n.of(AppearanceSlot.black, text).removedDefaults, [
      const Color(0xFF71727B),
    ]);
    expect(
      c.read(effectiveAppearanceColorProvider((slot, text))),
      const Color(0xFF71727B),
    );
    // 標準の色を削除した後は、その色も登録し直せる。
    expect(await n.addPreset(slot, text, const Color(0xFF71727B)), isTrue);
    expect(n.of(slot, text).presets, [const Color(0xFF71727B)]);
  });

  test('保存して読み込み直しても同じ', () async {
    final c = make();
    final n = c.read(appearanceColorsProvider.notifier);
    await n.apply(AppearanceSlot.black, text, const Color(0xFF445566));
    await n.addPreset(AppearanceSlot.black, onAccent, const Color(0xFF778899));
    await n.removeDefault(
      AppearanceSlot.soft,
      onAccent,
      const Color(0xFFEFEFF1),
    );
    final loaded = await loadInitialAppearanceColors();
    final c2 = ProviderContainer(
      overrides: [initialAppearanceColorsProvider.overrideWithValue(loaded)],
    );
    addTearDown(c2.dispose);
    final n2 = c2.read(appearanceColorsProvider.notifier);
    expect(n2.of(AppearanceSlot.black, text).applied, const Color(0xFF445566));
    expect(n2.of(AppearanceSlot.black, onAccent).presets, [
      const Color(0xFF778899),
    ]);
    expect(n2.of(AppearanceSlot.soft, onAccent).removedDefaults, [
      const Color(0xFFEFEFF1),
    ]);
  });

  test('外観の区分はテーマの明暗とダークの種類で決まる', () {
    expect(
      AppearanceSlot.of(ThemeMode.light, DarkVariant.black),
      AppearanceSlot.light,
    );
    expect(
      AppearanceSlot.of(ThemeMode.dark, DarkVariant.soft),
      AppearanceSlot.soft,
    );
  });
}
