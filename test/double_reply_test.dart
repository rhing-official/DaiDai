import 'package:daidai/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _m(String id, {String? reply2}) => Message(
  messageId: id,
  conversationId: 'c',
  conversationType: 'dm',
  senderId: 'u',
  content: 'こんにちは$id',
  contentType: 'text',
  replyToMessageId: 'a',
  replyToSenderId: 'ua',
  replyTo2MessageId: reply2,
  replyTo2SenderId: reply2 == null ? null : 'ub',
  replyTo2Snippet: reply2 == null ? null : 'snippet',
);

void main() {
  test('二重返信の2件目は保存・復元でき、無い時はキー自体を書かない', () {
    final json = _m('x', reply2: 'b').toJson();
    expect(json['replyTo2MessageId'], 'b');
    expect(json['replyTo2SenderId'], 'ub');
    final restored = Message.fromJson('x', {...json, 'sentAt': null});
    expect(restored.replyTo2MessageId, 'b');
    expect(restored.replyTo2Snippet, 'snippet');
    expect(restored.replyToMessageId, 'a');

    expect(_m('y').toJson().containsKey('replyTo2MessageId'), isFalse);
    expect(
      Message.fromJson('y', {
        ..._m('y').toJson(),
        'sentAt': null,
      }).replyTo2MessageId,
      isNull,
    );
  });

  test('2件目の返信先を1件目に結び付けて運べる', () {
    final first = _m('1');
    final second = _m('2');
    expect(secondReplyOf(first), isNull);
    setSecondReply(first, second);
    expect(secondReplyOf(first), same(second));
    setSecondReply(first, null);
    expect(secondReplyOf(first), isNull);
    expect(secondReplyOf(null), isNull);
  });
}
