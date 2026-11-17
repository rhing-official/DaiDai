import 'package:daidai/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _call(Map<String, dynamic> extra) => Message.fromJson('m1', {
  'conversationId': 'r1',
  'conversationType': 'dm',
  'senderId': 'u1',
  'content': '通話が終了しました',
  'contentType': 'call',
  ...extra,
});

void main() {
  test('callResultがmissedなら不在着信', () {
    expect(_call({'callResult': 'missed'}).isMissedCall, isTrue);
  });

  test('callResultが無い旧データは通話記録（不在着信ではない）', () {
    expect(_call({}).isMissedCall, isFalse);
    expect(_call({'callResult': 'completed'}).isMissedCall, isFalse);
  });
}
