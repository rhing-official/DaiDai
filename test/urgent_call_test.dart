import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/call.dart';
import 'package:daidai/models/group_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('緊急の発信の印は、Call・GroupCallの保存と読み込みで残る', () {
    final call = Call(
      callId: 'c',
      dmId: 'd',
      callerId: 'a',
      callerRhingSeed: 'a',
      calleeId: 'b',
      calleeRhingSeed: 'b',
      status: CallStatus.ringing,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      urgent: true,
    );
    expect(call.toJson()['urgent'], true);
    expect(Call.fromJson('c', call.toJson()).urgent, true);

    final group = GroupCall(
      groupCallId: 'g',
      groupId: 'x',
      initiatorId: 'a',
      memberIds: const ['a', 'b'],
      status: GroupCallStatus.active,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      urgent: true,
    );
    expect(group.toJson()['urgent'], true);
    expect(GroupCall.fromJson('g', group.toJson()).urgent, true);
  });

  test('通常の発信は、urgentを保存せず、読み込むとfalse', () {
    final call = Call(
      callId: 'c',
      dmId: 'd',
      callerId: 'a',
      callerRhingSeed: 'a',
      calleeId: 'b',
      calleeRhingSeed: 'b',
      status: CallStatus.ringing,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
    );
    expect(call.toJson().containsKey('urgent'), false);
    expect(Call.fromJson('c', call.toJson()).urgent, false);
  });
}
