import 'package:cloud_firestore/cloud_firestore.dart';

/// メッセージを既読にしたユーザー1人分の記録。
class MessageReadReceipt {
  const MessageReadReceipt({required this.userId, this.readAt});

  final String userId;
  final Timestamp? readAt;

  factory MessageReadReceipt.fromJson(Map<String, dynamic> json) {
    return MessageReadReceipt(
      userId: json['userId'] as String,
      readAt: json['readAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {'userId': userId, 'readAt': readAt};
}

class Message {
  const Message({
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    required this.senderId,
    this.senderRhingId,
    required this.content,
    required this.contentType,
    this.sentAt,
    this.deletedAt,
    this.silent = false,
    this.readBy = const [],
  });

  final String messageId;
  final String conversationId;
  final String conversationType; // dm | seat | room
  final String senderId;
  /// 送信者のRhing ID（グループ会話でアイコン・名前を表示するための非正規化）。
  final String? senderRhingId;
  final String content;
  final String contentType; // text | image | file | sticker | video
  final Timestamp? sentAt;
  final Timestamp? deletedAt;

  /// 送信者が「相手に通知せず送る」を選んだメッセージかどうか。
  /// FCMのプッシュ通知基盤が実装された際、このフラグが立っているメッセージは
  /// 通知を送らないようにする想定（実装内容.md参照）。
  final bool silent;

  /// このメッセージを読んだユーザーの一覧（送信者本人は含まない想定）。
  final List<MessageReadReceipt> readBy;

  factory Message.fromJson(String messageId, Map<String, dynamic> json) {
    return Message(
      messageId: messageId,
      conversationId: json['conversationId'] as String,
      conversationType: json['conversationType'] as String,
      senderId: json['senderId'] as String,
      senderRhingId: json['senderRhingId'] as String?,
      content: json['content'] as String,
      contentType: json['contentType'] as String,
      sentAt: json['sentAt'] as Timestamp?,
      deletedAt: json['deletedAt'] as Timestamp?,
      silent: json['silent'] as bool? ?? false,
      readBy: (json['readBy'] as List<dynamic>? ?? [])
          .map((e) => MessageReadReceipt.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'conversationType': conversationType,
      'senderId': senderId,
      'senderRhingId': senderRhingId,
      'content': content,
      'contentType': contentType,
      'sentAt': sentAt ?? FieldValue.serverTimestamp(),
      'deletedAt': deletedAt,
      'readBy': <Map<String, dynamic>>[],
      'isSpam': false,
      'silent': silent,
    };
  }
}
