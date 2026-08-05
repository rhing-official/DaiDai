import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message.fromJson/toJson', () {
    test('返信・編集・リアクションを含むラウンドトリップ', () {
      final original = Message(
        messageId: 'm1',
        conversationId: 'dm1',
        conversationType: 'dm',
        senderId: 'u1',
        senderRhingId: 'user1',
        content: '編集後の本文',
        contentType: 'text',
        sentAt: Timestamp.fromMillisecondsSinceEpoch(1000),
        replyToMessageId: 'm0',
        replyToSenderId: 'u2',
        replyToSenderRhingId: 'user2',
        replyToSnippet: '元のメッセージ',
        editedAt: Timestamp.fromMillisecondsSinceEpoch(2000),
        reactions: const {
          'u2': ['👍'],
          'u3': ['❤️', '😂'],
        },
      );

      final json = original.toJson();
      final restored = Message.fromJson('m1', json);

      expect(restored.replyToMessageId, 'm0');
      expect(restored.replyToSenderId, 'u2');
      expect(restored.replyToSenderRhingId, 'user2');
      expect(restored.replyToSnippet, '元のメッセージ');
      expect(restored.editedAt, original.editedAt);
      expect(restored.reactions, {
        'u2': ['👍'],
        'u3': ['❤️', '😂'],
      });
    });

    test('旧形式（reactions.\$userIdが単一の絵文字文字列）も後方互換で読める', () {
      final legacyJson = {
        'conversationId': 'dm1',
        'conversationType': 'dm',
        'senderId': 'u1',
        'content': 'こんにちは',
        'contentType': 'text',
        'sentAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'reactions': {'u2': '👍'},
      };

      final message = Message.fromJson('m1', legacyJson);

      expect(message.reactions, {
        'u2': ['👍'],
      });
    });

    test('新フィールドが存在しない既存ドキュメントでも欠損時デフォルトで復元できる', () {
      final legacyJson = {
        'conversationId': 'dm1',
        'conversationType': 'dm',
        'senderId': 'u1',
        'content': 'こんにちは',
        'contentType': 'text',
        'sentAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      };

      final message = Message.fromJson('m1', legacyJson);

      expect(message.replyToMessageId, isNull);
      expect(message.replyToSenderId, isNull);
      expect(message.replyToSenderRhingId, isNull);
      expect(message.replyToSnippet, isNull);
      expect(message.editedAt, isNull);
      expect(message.reactions, isEmpty);
    });

    test('返信なしの場合はreplyTo系フィールドがtoJsonでnullになる', () {
      const message = Message(
        messageId: 'm1',
        conversationId: 'dm1',
        conversationType: 'dm',
        senderId: 'u1',
        content: 'こんにちは',
        contentType: 'text',
      );

      final json = message.toJson();

      expect(json['replyToMessageId'], isNull);
      expect(json['replyToSenderId'], isNull);
      expect(json['replyToSenderRhingId'], isNull);
      expect(json['replyToSnippet'], isNull);
      expect(json['editedAt'], isNull);
      expect(json['reactions'], isEmpty);
    });
  });

  group('messageSnippetOf', () {
    test('80文字以内はそのまま返す', () {
      expect(messageSnippetOf('こんにちは'), 'こんにちは');
    });

    test('改行は空白に置き換える', () {
      expect(messageSnippetOf('1行目\n2行目'), '1行目 2行目');
    });

    test('80文字を超える場合は切り詰めて…を付ける', () {
      final longText = 'あ' * 100;
      final snippet = messageSnippetOf(longText);
      expect(snippet.length, 81);
      expect(snippet.endsWith('…'), isTrue);
    });
  });
}
