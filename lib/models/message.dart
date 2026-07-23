import 'package:cloud_firestore/cloud_firestore.dart';

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
