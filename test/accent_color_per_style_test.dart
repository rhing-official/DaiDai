import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legacy = Color(0xFFF08300);

ProviderContainer _container({
  Map<AppUiStyle, Color> byStyle = const {},
  AppUiStyle style = AppUiStyle.flat,
}) {
  final container = ProviderContainer(
    overrides: [
      initialAccentColorProvider.overrideWithValue(_legacy),
      initialAccentColorsByStyleProvider.overrideWithValue(byStyle),
      initialAppUiStyleProvider.overrideWithValue(style),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('スタイル別の保存値が無いスタイルは、共通の旧値から始まる', () {
    final container = _container();
    expect(container.read(accentColorProvider), _legacy);
  });

  test('色はUIスタイル毎に別々に持ち、切り替えるとそのスタイルの色に戻る', () async {
    final container = _container();
    await container
        .read(accentColorProvider.notifier)
        .setColor(const Color(0xFF112233));
    await container
        .read(appUiStyleProvider.notifier)
        .setStyle(AppUiStyle.glass);
    // ガラスはまだ選んでいないので旧値のまま（フラットの色は引き継がない）。
    expect(container.read(accentColorProvider), _legacy);
    await container
        .read(accentColorProvider.notifier)
        .setColor(const Color(0xFF445566));
    await container.read(appUiStyleProvider.notifier).setStyle(AppUiStyle.flat);
    expect(container.read(accentColorProvider), const Color(0xFF112233));
    await container
        .read(appUiStyleProvider.notifier)
        .setStyle(AppUiStyle.glass);
    expect(container.read(accentColorProvider), const Color(0xFF445566));
  });

  test('端末に保存したスタイル別の値を、起動時に読み込める', () async {
    final container = _container();
    await container
        .read(accentColorProvider.notifier)
        .setColor(const Color(0xFF112233));
    final loaded = await loadInitialAccentColorsByStyle();
    expect(loaded, {AppUiStyle.flat: const Color(0xFF112233)});
  });

  test('リモートの値は、スタイル別を優先し、無いスタイルだけ旧値を使う', () async {
    final container = _container();
    container.read(accentColorProvider);
    await container
        .read(accentColorProvider.notifier)
        .syncFromRemote(byStyle: {'flat': 0xFF010203}, legacy: 0xFF0A0B0C);
    expect(container.read(accentColorProvider), const Color(0xFF010203));
    await container
        .read(appUiStyleProvider.notifier)
        .setStyle(AppUiStyle.block);
    expect(container.read(accentColorProvider), const Color(0xFF0A0B0C));
  });
}
