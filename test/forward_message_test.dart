import 'package:daidai/models/message.dart';
import 'package:daidai/utils/forward_message.dart';
import 'package:daidai/utils/share_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Message _msg({
  String contentType = 'text',
  String content = 'こんにちは',
  MessageFileMetadata? file,
  List<MessageFileMetadata> attachments = const [],
  MessageStickerData? sticker,
}) => Message(
  messageId: 'm',
  conversationId: 'c',
  conversationType: 'dm',
  senderId: 'u',
  content: content,
  contentType: contentType,
  fileMetadata: file,
  attachments: attachments,
  stickerData: sticker,
);

const _file = MessageFileMetadata(
  url: 'https://example.com/a.png',
  fileName: 'a.png',
  extension: 'png',
  sizeBytes: 1,
  mimeType: 'image/png',
);

void main() {
  group('転送できる種類', () {
    test('本文・添付・複数添付・ぺったんは転送できる', () {
      expect(canForwardMessage(_msg()), isTrue);
      expect(
        canForwardMessage(_msg(contentType: 'image', file: _file)),
        isTrue,
      );
      expect(
        canForwardMessage(_msg(contentType: 'multi', attachments: [_file])),
        isTrue,
      );
      expect(
        canForwardMessage(
          _msg(
            contentType: 'sticker',
            sticker: const MessageStickerData(
              stickerId: 's',
              stickerUrl: 'https://example.com/s.png',
            ),
          ),
        ),
        isTrue,
      );
    });

    test('空の本文・通話履歴・通知カードは転送できない', () {
      expect(canForwardMessage(_msg(content: '  ')), isFalse);
      expect(canForwardMessage(_msg(contentType: 'call')), isFalse);
      expect(canForwardMessage(_msg(contentType: 'poll')), isFalse);
      expect(canForwardMessage(_msg(contentType: 'image')), isFalse);
    });
  });

  group('共有できる種類', () {
    test('添付と、本文だけのメッセージは共有できる', () {
      expect(shareableMessage(_msg()), isTrue);
      expect(shareableMessage(_msg(contentType: 'image', file: _file)), isTrue);
    });

    test('空の本文・通話履歴は共有できない', () {
      expect(shareableMessage(_msg(content: '')), isFalse);
      expect(shareableMessage(_msg(contentType: 'call')), isFalse);
    });
  });
}
