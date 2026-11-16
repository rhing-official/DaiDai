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

  test('タブ・選んだアルバム・最後に再生した曲を端末に保存して、読み込み直せる', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(bgmPreferencesProvider.notifier);
    await notifier.saveTab(2);
    await notifier.saveAlbumId('album-1');
    await notifier.saveLastPlayed(
      const BgmLastPlayed(
        trackId: 't1',
        positionMs: 42000,
        queueAlbumId: 'album-1',
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('bgmTab'), 2);
    expect(prefs.getString('bgmAlbumId'), 'album-1');
    expect(prefs.getString('bgmLastTrackId'), 't1');
    expect(prefs.getInt('bgmLastPositionMs'), 42000);

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    reloaded.read(bgmPreferencesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final s = reloaded.read(bgmPreferencesProvider);
    expect(s.tab, 2);
    expect(s.albumId, 'album-1');
    expect(s.lastPlayed?.trackId, 't1');
    expect(s.lastPlayed?.positionMs, 42000);
    expect(s.lastPlayed?.queueAlbumId, 'album-1');

    await notifier.saveLastPlayed(null);
    expect(prefs.getString('bgmLastTrackId'), isNull);
  });

  test('アカウントの設定にはタブだけが入り、曲・アルバムの情報は入らない', () {
    final p = AppUserPreferences.fromJson({'bgmTab': 1});
    expect(p.bgmTab, 1);
    final json = AppUserPreferences(bgmTab: 2, bgmVolume: 0.5).toJson();
    expect(json['bgmTab'], 2);
    for (final key in json.keys) {
      expect(key.toLowerCase().contains('track'), isFalse);
      expect(key.toLowerCase().contains('album'), isFalse);
    }
  });
}
