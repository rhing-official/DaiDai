import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/rtc_config.dart';

List<dynamic> _servers(Map<String, dynamic> config) =>
    config['iceServers'] as List<dynamic>;

void main() {
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
