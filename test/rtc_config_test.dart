import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/rtc_config.dart';

List<dynamic> _servers(Map<String, dynamic> config) =>
    config['iceServers'] as List<dynamic>;

void main() {
  cachedIceServersLoaderTests();
  test('取得元が無ければSTUNだけ', () async {
    final config = await loadRtcConfiguration(null);
    expect(_servers(config), [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]);
  });

  test('TURNを取得できたらiceServersに足す', () async {
    final config = await loadRtcConfiguration(
      () async => [
        {
          'urls': ['turn:turn.example.com:3478'],
          'username': 'u',
          'credential': 'c',
        },
      ],
    );
    expect(_servers(config), [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': ['turn:turn.example.com:3478'],
        'username': 'u',
        'credential': 'c',
      },
    ]);
  });

  test('取得に失敗してもSTUNだけで続行する', () async {
    final config = await loadRtcConfiguration(() async => throw Exception('x'));
    expect(_servers(config), [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]);
  });

  test('取得が時間切れでもSTUNだけで続行する', () async {
    final config = await loadRtcConfiguration(
      () => Future.delayed(
        const Duration(seconds: 1),
        () => <Map<String, dynamic>>[
          {'urls': 'turn:late'},
        ],
      ),
      timeout: const Duration(milliseconds: 10),
    );
    expect(_servers(config), [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]);
  });
}

void cachedIceServersLoaderTests() {
  test('CachedIceServersLoader: 期限内は取得済みの結果を使い回す', () async {
    var calls = 0;
    var now = DateTime(2026, 10, 31, 12);
    final loader = CachedIceServersLoader(
      () async {
        calls++;
        return [
          {'urls': 'turn:x'},
        ];
      },
      ttl: const Duration(hours: 1),
      now: () => now,
    );
    await loader();
    await loader();
    expect(calls, 1);
    now = now.add(const Duration(hours: 2));
    await loader();
    expect(calls, 2);
  });

  test('CachedIceServersLoader: 失敗は覚えない', () async {
    var calls = 0;
    final loader = CachedIceServersLoader(() async {
      calls++;
      if (calls == 1) throw Exception('x');
      return [];
    });
    await expectLater(loader(), throwsException);
    await loader();
    expect(calls, 2);
  });
}
