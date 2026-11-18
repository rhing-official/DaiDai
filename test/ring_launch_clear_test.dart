import 'package:daidai/features/call/ring_launch_overlay.dart';
import 'package:daidai/models/call.dart';
import 'package:daidai/models/group_call.dart';
import 'package:flutter_test/flutter_test.dart';

Call _call(CallStatus status) => Call(
  callId: 'c1',
  dmId: 'd1',
  callerId: 'a',
  callerRhingSeed: 'a',
  calleeId: 'b',
  calleeRhingSeed: 'b',
  status: status,
);

GroupCall _group(String id, GroupCallStatus status) => GroupCall(
  groupCallId: id,
  groupId: 'g',
  initiatorId: 'a',
  memberIds: const ['a', 'b'],
  status: status,
);

void main() {
  group('一対', () {
    test('呼び出し中のままなら閉じない', () {
      expect(
        shouldClearRingLaunch(
          isGroup: false,
          callId: 'c1',
          call: _call(CallStatus.ringing),
          seenActive: false,
        ),
        isFalse,
      );
    });
    test('キャンセル（終了）・不在・拒否・応答で閉じる', () {
      for (final s in [
        CallStatus.ended,
        CallStatus.missed,
        CallStatus.declined,
        CallStatus.active,
      ]) {
        expect(
          shouldClearRingLaunch(
            isGroup: false,
            callId: 'c1',
            call: _call(s),
            seenActive: false,
          ),
          isTrue,
        );
      }
    });
    test('見る前の「無い」は閉じず、一度見た後の「無い」は閉じる', () {
      expect(
        shouldClearRingLaunch(isGroup: false, callId: 'c1', seenActive: false),
        isFalse,
      );
      expect(
        shouldClearRingLaunch(isGroup: false, callId: 'c1', seenActive: true),
        isTrue,
      );
    });
  });

  group('広場', () {
    test('同じ通話が進行中なら閉じない', () {
      expect(
        shouldClearRingLaunch(
          isGroup: true,
          callId: 'g1',
          activeGroupCall: _group('g1', GroupCallStatus.active),
          seenActive: true,
        ),
        isFalse,
      );
    });
    test('進行中の通話が無くなった（一度見た後）・別の通話・終了で閉じる', () {
      expect(
        shouldClearRingLaunch(isGroup: true, callId: 'g1', seenActive: true),
        isTrue,
      );
      expect(
        shouldClearRingLaunch(isGroup: true, callId: 'g1', seenActive: false),
        isFalse,
      );
      expect(
        shouldClearRingLaunch(
          isGroup: true,
          callId: 'g1',
          activeGroupCall: _group('g2', GroupCallStatus.active),
          seenActive: false,
        ),
        isTrue,
      );
      expect(
        shouldClearRingLaunch(
          isGroup: true,
          callId: 'g1',
          activeGroupCall: _group('g1', GroupCallStatus.ended),
          seenActive: false,
        ),
        isTrue,
      );
    });
  });
}
