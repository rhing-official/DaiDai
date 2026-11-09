import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/utils/last_message_update.dart';
import 'package:flutter_test/flutter_test.dart';

Message _msg(
  String id,
  int seconds, {
  String type = 'text',
  String content = 'hi',
  String sender = 'a',
}) => Message.fromJson(id, {
  'conversationId': 'c',
  'conversationType': 'room',
  'senderId': sender,
  'content': content,
  'contentType': type,
  'sentAt': Timestamp(seconds, 0),
});

void main() {
  test('取り消すのが最終メッセージの時だけ、最終メッセージとみなす', () {
    final m = _msg('1', 100);
    expect(
      LastMessageUpdate.isLast(
        target: m,
        conversationLastAt: Timestamp(100, 0),
        conversationLastSenderId: 'a',
      ),
      isTrue,
    );
    expect(
      LastMessageUpdate.isLast(
        target: m,
        conversationLastAt: Timestamp(200, 0),
        conversationLastSenderId: 'a',
      ),
      isFalse,
    );
    expect(
      LastMessageUpdate.isLast(
        target: m,
        conversationLastAt: Timestamp(100, 0),
        conversationLastSenderId: 'b',
      ),
      isFalse,
    );
  });

  test('残ったメッセージのうち、最も新しいものを選ぶ', () {
    final newest = LastMessageUpdate.newest([
      _msg('1', 10),
      _msg('2', 30),
      _msg('3', 20),
    ]);
    expect(newest?.messageId, '2');
    expect(LastMessageUpdate.newest(const []), isNull);
  });

  test('テキストにはプレビューを入れ、画像には入れない。残りが無ければ4項目を消す', () {
    final text = LastMessageUpdate.fieldsFor(_msg('1', 10, content: 'hello'));
    expect(text['lastMessagePreview'], 'hello');
    expect(text['lastMessageContentType'], 'text');
    final image = LastMessageUpdate.fieldsFor(
      _msg('2', 10, type: 'image', content: ''),
    );
    expect(image['lastMessagePreview'], isNull);
    final cleared = LastMessageUpdate.fieldsFor(null);
    expect(
      cleared.keys,
      containsAll([
        'lastMessageAt',
        'lastMessageSenderId',
        'lastMessageContentType',
        'lastMessagePreview',
      ]),
    );
    expect(cleared['lastMessageAt'], isA<FieldValue>());
  });
}
