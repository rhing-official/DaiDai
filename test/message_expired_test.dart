import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/utils/forward_message.dart';
import 'package:daidai/utils/share_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({bool expired = false}) => {
  'conversationId': 'c',
  'conversationType': 'dm',
  'senderId': 'u',
  'content': 'a.webp',
  'contentType': 'image',
  'fileMetadata': {
    'url': 'https://example.com/a.webp',
    'fileName': 'a.webp',
    'extension': 'webp',
    'sizeBytes': 10,
    'mimeType': 'image/webp',
    'compressionType': 'webp',
  },
  if (expired) 'attachmentsExpired': true,
  'expiresAt': Timestamp.fromMillisecondsSinceEpoch(1000),
};

void main() {
  test('期限と、期限切れの印を読む。書き出さない（サーバーだけが付ける）', () {
    final m = Message.fromJson('m', _json(expired: true));
    expect(m.attachmentsExpired, isTrue);
    expect(m.expiresAt, isNotNull);
    final out = m.toJson();
    expect(out.containsKey('expiresAt'), isFalse);
    expect(out.containsKey('attachmentsExpired'), isFalse);
  });

  test('印が無ければ、期限切れではない', () {
    final m = Message.fromJson('m', _json());
    expect(m.attachmentsExpired, isFalse);
  });

  test('期限切れの添付は、共有も転送も出来ない', () {
    final expired = Message.fromJson('m', _json(expired: true));
    final live = Message.fromJson('m', _json());
    expect(shareableMessage(expired), isFalse);
    expect(canForwardMessage(expired), isFalse);
    expect(shareableMessage(live), isTrue);
    expect(canForwardMessage(live), isTrue);
  });
}
