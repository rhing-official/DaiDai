import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/features/call/bgm/bgm_queue.dart';
import 'package:daidai/models/app_user_preferences.dart';
import 'package:daidai/providers/bgm_preferences_provider.dart';

void main() {
  test('再生順の名前から復元する（不明はnull）', () {
    expect(bgmPlayOrderFromName('shuffle'), BgmPlayOrder.shuffle);
    expect(bgmPlayOrderFromName('x'), isNull);
    expect(bgmPlayOrderFromName(null), isNull);
  });

  test('アカウントの設定に、BGMの音量・再生順が入る', () {
    final p = AppUserPreferences.fromJson({
      'bgmVolume': 0.25,
      'bgmPlayOrder': 'repeatOne',
    });
    expect(p.bgmVolume, 0.25);
    expect(p.toJson()['bgmPlayOrder'], 'repeatOne');
    expect(AppUserPreferences.empty.toJson().containsKey('bgmVolume'), isFalse);
  });

  test('端末に保存した前回の状態を読み込む', () async {
    SharedPreferences.setMockInitialValues({
      'bgmVolume': 0.8,
      'bgmPlayOrder': 'shuffle',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bgmPreferencesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = container.read(bgmPreferencesProvider);
    expect(s.volume, 0.8);
    expect(s.order, BgmPlayOrder.shuffle);
  });
}
