import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/call.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 17, 12);

Timestamp _ago(Duration d) => Timestamp.fromDate(_now.subtract(d));

Call _call({
  CallStatus status = CallStatus.active,
  Timestamp? createdAt,
  Timestamp? connectedAt,
  Timestamp? callerSeenAt,
  Timestamp? calleeSeenAt,
}) => Call(
  callId: 'c',
  dmId: 'd',
  callerId: 'a',
  callerRhingSeed: 'a',
  calleeId: 'b',
  calleeRhingSeed: 'b',
  status: status,
  createdAt: createdAt,
  connectedAt: connectedAt,
  callerSeenAt: callerSeenAt,
  calleeSeenAt: calleeSeenAt,
);

void main() {
  test('ハートビートが新しい通話は生きている（片方だけでもよい）', () {
    expect(
      isOneToOneCallLive(
        _call(callerSeenAt: _ago(const Duration(seconds: 10))),
        _now,
      ),
      isTrue,
    );
    expect(
      isOneToOneCallLive(
        _call(
          callerSeenAt: _ago(const Duration(minutes: 10)),
          calleeSeenAt: _ago(const Duration(seconds: 20)),
        ),
        _now,
      ),
      isTrue,
    );
  });

  test('ハートビートが両方とも途絶えた通話は死んでいる', () {
    expect(
      isOneToOneCallLive(
        _call(
          callerSeenAt: _ago(const Duration(minutes: 2)),
          calleeSeenAt: _ago(const Duration(minutes: 3)),
        ),
        _now,
      ),
      isFalse,
    );
  });

  test('ハートビートが無い通話は、3時間以内なら生きている・超えたら死んでいる', () {
    expect(
      isOneToOneCallLive(
        _call(connectedAt: _ago(const Duration(hours: 1))),
        _now,
      ),
      isTrue,
    );
    expect(
      isOneToOneCallLive(
        _call(connectedAt: _ago(const Duration(hours: 4))),
        _now,
      ),
      isFalse,
    );
    // 応答時刻が無ければ作成時刻で判定する。
    expect(
      isOneToOneCallLive(
        _call(createdAt: _ago(const Duration(hours: 5))),
        _now,
      ),
      isFalse,
    );
  });

  test('時刻がどれも無い（書き込み直後）なら生きているとみなす', () {
    expect(isOneToOneCallLive(_call(), _now), isTrue);
  });

  test('activeでない通話は生きていない', () {
    expect(
      isOneToOneCallLive(
        _call(
          status: CallStatus.ended,
          callerSeenAt: _ago(const Duration(seconds: 1)),
        ),
        _now,
      ),
      isFalse,
    );
  });
}
