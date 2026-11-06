import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/message.dart';

/// `sentAt`はサーバー時刻のプレースホルダ（`FieldValue`）で復元出来ないため除く。
Map<String, dynamic> _stored(Message m) => {...m.toJson()}..remove('sentAt');

void main() {
  Message base({String? caption}) => Message(
    messageId: 'm',
    conversationId: 'c',
    conversationType: 'dm',
    senderId: 'u',
    content: 'a.png',
    contentType: 'image',
    caption: caption,
  );

  test('キャプションが無い時は保存しない', () {
    expect(base().toJson().containsKey('caption'), isFalse);
    expect(Message.fromJson('m', _stored(base())).caption, isNull);
  });

  test('キャプションは保存・復元でき、contentはファイル名のまま', () {
    final json = _stored(base(caption: 'こんにちは'));
    expect(json['caption'], 'こんにちは');
    final restored = Message.fromJson('m', json);
    expect(restored.caption, 'こんにちは');
    expect(restored.content, 'a.png');
  });
}
