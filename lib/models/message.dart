import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  const Message({
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    required this.senderId,
    required this.content,
    required this.contentType,
    this.sentAt,
    this.deletedAt,
  });

  final String messageId;
  final String conversationId;
  final String conversationType; // dm | seat | room
  final String senderId;
  final String content;
  final String contentType; // text | image | file | sticker | video
  final Timestamp? sentAt;
  final Timestamp? deletedAt;

  factory Message.fromJson(String messageId, Map<String, dynamic> json) {
    return Message(
      messageId: messageId,
      conversationId: json['conversationId'] as String,
      conversationType: json['conversationType'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      contentType: json['contentType'] as String,
      sentAt: json['sentAt'] as Timestamp?,
      deletedAt: json['deletedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'conversationType': conversationType,
      'senderId': senderId,
      'content': content,
      'contentType': contentType,
      'sentAt': sentAt ?? FieldValue.serverTimestamp(),
      'deletedAt': deletedAt,
      'readBy': <Map<String, dynamic>>[],
      'isSpam': false,
    };
  }
}
