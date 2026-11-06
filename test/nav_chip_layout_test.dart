import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/models/nav_chip_layout.dart';
import 'package:daidai/providers/nav_chip_layout_provider.dart';

void main() {
  test('並びは不明・重複を捨て、足りないタブを標準の順で補う', () {
    expect(normalizeNavChipOrder(null), HomeTabId.values);
    expect(normalizeNavChipOrder(['settings', 'settings', 'x', 'talk']), [
      HomeTabId.settings,
      HomeTabId.talk,
      HomeTabId.profile,
    ]);
  });

  test('タブの論理インデックスはenumの宣言順（ホーム画面の前提）', () {
    expect(HomeTabId.talk.index, 0);
    expect(HomeTabId.profile.index, 1);
    expect(HomeTabId.settings.index, 2);
  });

  test('揃えの標準は中央、不明な値も中央', () {
    expect(NavChipAlignment.fromName(null), NavChipAlignment.center);
    expect(NavChipAlignment.fromName('zzz'), NavChipAlignment.center);
    expect(NavChipAlignment.fromName('end'), NavChipAlignment.end);
  });

  test('保存して読み直すと同じ揃え・並びになる', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(navChipLayoutProvider.notifier);
    await notifier.setAlignment(NavChipAlignment.end);
    await notifier.setOrder([
      HomeTabId.settings,
      HomeTabId.talk,
      HomeTabId.profile,
    ]);
    final loaded = await loadInitialNavChipLayout();
    expect(loaded.alignment, NavChipAlignment.end);
    expect(loaded.order, [
      HomeTabId.settings,
      HomeTabId.talk,
      HomeTabId.profile,
    ]);
  });

  test('横表示の揃えは縦表示と別に保存され、未保存の端末は縦表示の値を引き継ぐ', () async {
    SharedPreferences.setMockInitialValues({'navChipAlignment': 'start'});
    final migrated = await loadInitialNavChipLayout();
    expect(migrated.alignment, NavChipAlignment.start);
    expect(migrated.wideAlignment, NavChipAlignment.start);

    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(navChipLayoutProvider.notifier);
    await notifier.setAlignment(NavChipAlignment.start);
    await notifier.setWideAlignment(NavChipAlignment.end);
    final loaded = await loadInitialNavChipLayout();
    expect(loaded.alignment, NavChipAlignment.start);
    expect(loaded.wideAlignment, NavChipAlignment.end);
  });
}
