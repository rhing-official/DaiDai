import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';

void main() {
  test('不明な値は標準のアイコン+寄合一覧になる', () {
    expect(TalksListLayoutStyle.fromName(null), TalksListLayoutStyle.iconSplit);
    expect(
      TalksListLayoutStyle.fromName('zzz'),
      TalksListLayoutStyle.iconSplit,
    );
    expect(
      TalksListLayoutStyle.fromName('standard'),
      TalksListLayoutStyle.standard,
    );
  });

  test('縦画面用・横画面用は別々に保存され、読み直すとそれぞれ保持される', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(talksListLayoutStyleProvider.notifier)
        .setStyle(TalksListLayoutStyle.standard);
    await container
        .read(talksListLayoutStyleWideProvider.notifier)
        .setStyle(TalksListLayoutStyle.iconSplit);

    expect(
      await loadInitialTalksListLayoutStyle(),
      TalksListLayoutStyle.standard,
    );
    expect(
      await loadInitialTalksListLayoutStyleWide(),
      TalksListLayoutStyle.iconSplit,
    );
  });

  test('横画面用のキーが未保存の端末は、縦画面用の値を引き継ぐ', () async {
    SharedPreferences.setMockInitialValues({
      'talksListLayoutStyle': 'standard',
    });
    expect(
      await loadInitialTalksListLayoutStyle(),
      TalksListLayoutStyle.standard,
    );
    expect(
      await loadInitialTalksListLayoutStyleWide(),
      TalksListLayoutStyle.standard,
    );
  });

  test('横画面用のキーが保存済みなら、縦画面用の値とは別に扱う', () async {
    SharedPreferences.setMockInitialValues({
      'talksListLayoutStyle': 'standard',
      'talksListLayoutStyleWide': 'iconSplit',
    });
    expect(
      await loadInitialTalksListLayoutStyle(),
      TalksListLayoutStyle.standard,
    );
    expect(
      await loadInitialTalksListLayoutStyleWide(),
      TalksListLayoutStyle.iconSplit,
    );
  });
}
