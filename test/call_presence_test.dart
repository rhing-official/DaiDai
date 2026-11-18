import 'package:daidai/features/call/call_participants_strip.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/group_call.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

CallParticipant _p(String id, {DateTime? lastSeen}) => CallParticipant(
  userId: id,
  rhingSeed: id,
  lastSeenAt: lastSeen == null ? null : Timestamp.fromDate(lastSeen),
);

void main() {
  _roomIdRoundTrip();
  group('通話に入っている人の呼び名の文', () {
    test('1人・2人・3人以上', () {
      expect(CallParticipantsStrip.namesLabel(Strings.ja, ['A']), 'A');
      expect(CallParticipantsStrip.namesLabel(Strings.ja, ['A', 'B']), 'A・B');
      expect(
        CallParticipantsStrip.namesLabel(Strings.ja, ['A', 'B', 'C']),
        'Aほか2人',
      );
      expect(CallParticipantsStrip.namesLabel(Strings.ja, []), '');
    });
  });

  group('liveParticipants', () {
    test('ハートビートが途絶えた人を除く', () {
      final now = DateTime(2026, 11, 17, 12);
      final live = liveParticipants([
        _p('fresh', lastSeen: now.subtract(const Duration(seconds: 10))),
        _p('stale', lastSeen: now.subtract(const Duration(minutes: 5))),
        _p('unknown'),
      ], now);
      expect(live.map((p) => p.userId), ['fresh', 'unknown']);
      expect(liveParticipantCount([_p('a'), _p('b')], now), 2);
    });
  });
}

void _roomIdRoundTrip() {
  group('通話を始めた寄合のid', () {
    test('GroupCallのroomIdはtoJson/fromJsonで往復し、無ければ書かない', () {
      const withRoom = GroupCall(
        groupCallId: 'g1',
        groupId: 'grp',
        initiatorId: 'u1',
        memberIds: ['u1'],
        status: GroupCallStatus.active,
        roomId: 'r1',
      );
      expect(withRoom.toJson()['roomId'], 'r1');
      final restored = GroupCall.fromJson('g1', {
        ...withRoom.toJson(),
        'createdAt': null,
      });
      expect(restored.roomId, 'r1');

      const without = GroupCall(
        groupCallId: 'g2',
        groupId: 'grp',
        initiatorId: 'u1',
        memberIds: ['u1'],
        status: GroupCallStatus.active,
      );
      expect(without.toJson().containsKey('roomId'), isFalse);
      expect(
        GroupCall.fromJson('g2', {
          ...without.toJson(),
          'createdAt': null,
        }).roomId,
        isNull,
      );
    });
  });
}
