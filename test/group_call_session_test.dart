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
}
