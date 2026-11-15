import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/peer_watchdog.dart';

void main() {
  PeerWatchdogAction act({
    bool established = false,
    int seconds = 0,
    bool restarted = false,
    int recreates = 0,
  }) => peerWatchdogAction(
    established: established,
    sinceStageStart: Duration(seconds: seconds),
    iceRestarted: restarted,
    recreates: recreates,
  );

  test('確立済み・8秒未満は何もしない', () {
    expect(act(established: true, seconds: 30), PeerWatchdogAction.none);
    expect(act(seconds: 7), PeerWatchdogAction.none);
  });

  test('8秒で確立しなければ、まずICEを再起動する', () {
    expect(act(seconds: 8), PeerWatchdogAction.restartIce);
  });

  test('再起動後さらに8秒で確立しなければ、接続を作り直す', () {
    expect(act(seconds: 8, restarted: true), PeerWatchdogAction.recreate);
    expect(act(seconds: 3, restarted: true), PeerWatchdogAction.none);
  });

  test('作り直しは2回まで。それでも駄目なら諦める', () {
    expect(
      act(seconds: 8, restarted: true, recreates: 1),
      PeerWatchdogAction.recreate,
    );
    expect(
      act(seconds: 8, restarted: true, recreates: 2),
      PeerWatchdogAction.giveUp,
    );
  });
}
