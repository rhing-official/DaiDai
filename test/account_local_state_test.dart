import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/utils/account_local_state.dart';

void main() {
  Future<SharedPreferences> start(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferences.getInstance();
  }

  test('持ち主が未登録の初回は、消さずに今のアカウントのものとして登録する', () async {
    final prefs = await start({'appTextSize': 1.2});
    expect(await swapLocalStateTo('a'), isFalse);
    expect(prefs.getDouble('appTextSize'), 1.2);
    expect(prefs.getString('localStateOwnerUid'), 'a');
  });

  test('同じ持ち主なら何もしない', () async {
    final prefs = await start({'localStateOwnerUid': 'a', 'k': 'v'});
    expect(await swapLocalStateTo('a'), isFalse);
    expect(prefs.getString('k'), 'v');
  });

  test('A→Bで設定が入れ替わり、B→Aで全ての型が復元される', () async {
    final prefs = await start({
      'localStateOwnerUid': 'a',
      's': 'x',
      'i': 3,
      'd': 1.5,
      'b': true,
      'l': ['p', 'q'],
    });
    expect(await swapLocalStateTo('b'), isTrue);
    expect(prefs.getString('s'), isNull);
    expect(prefs.getInt('i'), isNull);
    expect(prefs.getString('localStateOwnerUid'), 'b');

    await prefs.setString('s', 'y');
    expect(await swapLocalStateTo('a'), isTrue);
    expect(prefs.getString('s'), 'x');
    expect(prefs.getInt('i'), 3);
    expect(prefs.getDouble('d'), 1.5);
    expect(prefs.getBool('b'), isTrue);
    expect(prefs.getStringList('l'), ['p', 'q']);

    expect(await swapLocalStateTo('b'), isTrue);
    expect(prefs.getString('s'), 'y');
  });

  test('パスコードと端末の通知チャンネルの印は退避も削除もしない', () async {
    final prefs = await start({
      'localStateOwnerUid': 'a',
      'passcodeLock.x': 'keep',
      'notificationSoundCustomChannelReadyUrl': 'u',
      's': 'x',
    });
    await swapLocalStateTo('b');
    expect(prefs.getString('passcodeLock.x'), 'keep');
    expect(prefs.getString('notificationSoundCustomChannelReadyUrl'), 'u');
    expect(prefs.getString('s'), isNull);
  });
}
