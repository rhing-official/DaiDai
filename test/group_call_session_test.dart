import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/group_call.dart';

void main() {
  group('isSessionTakenOver', () {
    test('自分のsessionIdと同じ、または無ければ乗っ取りではない', () {
      expect(
        isSessionTakenOver(mySessionId: 'a', participantSessionId: 'a'),
        isFalse,
      );
      expect(
        isSessionTakenOver(mySessionId: 'a', participantSessionId: null),
        isFalse,
      );
    });

    test('別のsessionIdなら乗っ取り（別の端末が入り直した）', () {
      expect(
        isSessionTakenOver(mySessionId: 'a', participantSessionId: 'b'),
        isTrue,
      );
    });
  });

  group('CallParticipant.sessionId', () {
    test('JSONから読み、あれば書き出す。無ければ書き出さない', () {
      final withSession = CallParticipant.fromJson('u1', {
        'rhingSeed': 'alice',
        'sessionId': 's1',
      });
      expect(withSession.sessionId, 's1');
      expect(withSession.toJson()['sessionId'], 's1');

      final legacy = CallParticipant.fromJson('u1', {'rhingSeed': 'alice'});
      expect(legacy.sessionId, isNull);
      expect(legacy.toJson().containsKey('sessionId'), isFalse);
    });
  });

  group('liveParticipantCount', () {
    final now = DateTime(2026, 10, 21, 12);
    CallParticipant at(DateTime? seen) => CallParticipant(
      userId: 'u${seen?.second}',
      rhingSeed: 's',
      lastSeenAt: seen == null ? null : Timestamp.fromDate(seen),
    );

    test('ハートビートが45秒以内の人と、まだ記録が無い人を数え、途絶えた人は数えない', () {
      expect(
        liveParticipantCount([
          at(now.subtract(const Duration(seconds: 10))),
          at(now.subtract(const Duration(seconds: 44))),
          at(now.subtract(const Duration(seconds: 46))),
          at(null),
        ], now),
        3,
      );
    });

    test('誰もいなければ0', () {
      expect(liveParticipantCount(const [], now), 0);
    });
  });

  group('isGroupCallAbandoned', () {
    final now = DateTime(2026, 10, 22, 12);
    Timestamp ago(int sec) =>
        Timestamp.fromDate(now.subtract(Duration(seconds: sec)));
    CallParticipant seen(int sec) =>
        CallParticipant(userId: 'u', rhingSeed: 's', lastSeenAt: ago(sec));

    test('作成から60秒以内、または作成時刻が未確定なら放棄とみなさない', () {
      expect(
        isGroupCallAbandoned(participants: [], createdAt: ago(30), now: now),
        isFalse,
      );
      expect(
        isGroupCallAbandoned(participants: [], createdAt: null, now: now),
        isFalse,
      );
    });

    test('猶予後に参加者が0人、または全員ハートビート切れなら放棄', () {
      expect(
        isGroupCallAbandoned(participants: [], createdAt: ago(120), now: now),
        isTrue,
      );
      expect(
        isGroupCallAbandoned(
          participants: [seen(100), seen(60)],
          createdAt: ago(600),
          now: now,
        ),
        isTrue,
      );
    });

    test('生きている参加者が1人でもいれば放棄ではない', () {
      expect(
        isGroupCallAbandoned(
          participants: [seen(100), seen(5)],
          createdAt: ago(600),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
