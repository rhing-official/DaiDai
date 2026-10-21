import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/call.dart';

void main() {
  test('自分・相手のRhing SeedとuserIdを、発信側・着信側どちらからでも取れる', () {
    final call = Call.fromJson('c1', {
      'callerId': 'u1',
      'callerRhingSeed': 'alice',
      'calleeId': 'u2',
      'calleeRhingSeed': 'bob',
      'dmId': 'dm1',
      'status': 'ringing',
    });
    expect(call.myRhingSeed('u1'), 'alice');
    expect(call.otherRhingSeed('u1'), 'bob');
    expect(call.otherUserId('u1'), 'u2');
    expect(call.myRhingSeed('u2'), 'bob');
    expect(call.otherRhingSeed('u2'), 'alice');
    expect(call.otherUserId('u2'), 'u1');
  });
}
