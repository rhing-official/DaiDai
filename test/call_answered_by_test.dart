import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/call.dart';

void main() {
  Map<String, dynamic> base() => {
    'callerId': 'a',
    'callerRhingSeed': 'a',
    'calleeId': 'b',
    'calleeRhingSeed': 'b',
    'status': 'ringing',
  };

  test('answeredBy は、無ければnull、あればそのまま読む', () {
    expect(Call.fromJson('c', base()).answeredBy, isNull);
    expect(
      Call.fromJson('c', {...base(), 'answeredBy': 'dev-1'}).answeredBy,
      'dev-1',
    );
  });
}
