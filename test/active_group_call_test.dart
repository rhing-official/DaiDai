import 'package:daidai/models/group_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> data(String status) => {
    'groupId': 'g',
    'initiatorId': 'u',
    'memberIds': ['u', 'v'],
    'status': status,
  };

  test('進行中の通話だけが返り、文書が無い・終了済みはnull', () {
    expect(activeGroupCallFromData('c1', null), isNull);
    expect(activeGroupCallFromData('c1', data('ended')), isNull);
    final call = activeGroupCallFromData('c1', data('active'));
    expect(call?.groupCallId, 'c1');
    expect(call?.groupId, 'g');
  });
}
