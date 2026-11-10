import 'package:cloud_firestore/cloud_firestore.dart';

/// 送信予定の1件（`scheduledMessages/{id}`、2026-11-10追加）。時刻になるとCloud Functionsが
/// [message]を寄合へ送る。作成・日時の変更・取り消しは予定した本人（[createdBy]）だけ。
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.scope,
    required this.conversationId,
    required this.roomId,
    required this.messageId,
    required this.message,
    required this.createdBy,
    required this.sendAt,
    required this.status,
    this.failReason,
    this.lastMessagePreview,
  });

  final String id;

  /// `dm`か`group`。
  final String scope;
  final String conversationId;
  final String roomId;
  final String messageId;

  /// 送るメッセージ（`Message.toJson()`から`sentAt`を除いたもの）。
  final Map<String, dynamic> message;
  final String createdBy;
  final DateTime sendAt;

  /// `pending`（送信待ち）・`sending`（送信中）・`failed`（送れなかった）。
  final String status;

  /// 失敗の理由（`notMember`・`conversationMissing`・`invalid`）。
  final String? failReason;
  final String? lastMessagePreview;

  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';

  /// メッセージの種類（text・image・video・file・multi・sticker）。
  String get contentType => (message['contentType'] as String?) ?? 'text';

  /// 本文（添付・ぺったんでは、ファイル名・ぺったんの名前）。
  String get content => (message['content'] as String?) ?? '';

  factory ScheduledMessage.fromJson(String id, Map<String, dynamic> json) {
    return ScheduledMessage(
      id: id,
      scope: json['scope'] as String? ?? 'dm',
      conversationId: json['conversationId'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      messageId: json['messageId'] as String? ?? '',
      message: Map<String, dynamic>.from(json['message'] as Map? ?? const {}),
      createdBy: json['createdBy'] as String? ?? '',
      sendAt: (json['sendAt'] as Timestamp).toDate(),
      status: json['status'] as String? ?? 'pending',
      failReason: json['failReason'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String?,
    );
  }

  /// 予定として保存する内容（作成時）。[message]は`Message.toJson()`の結果（`sentAt`は除く）。
  static Map<String, dynamic> toCreateJson({
    required String scope,
    required String conversationId,
    required String roomId,
    required String messageId,
    required Map<String, dynamic> message,
    required String createdBy,
    required DateTime sendAt,
    required String lastMessageContentType,
    String? lastMessagePreview,
  }) {
    return {
      'scope': scope,
      'conversationId': conversationId,
      'roomId': roomId,
      'messageId': messageId,
      'message': {...message}..remove('sentAt'),
      'createdBy': createdBy,
      'sendAt': Timestamp.fromDate(sendAt),
      'status': 'pending',
      'lastMessageContentType': lastMessageContentType,
      'lastMessagePreview': lastMessagePreview,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

/// 予定できる最大の先（1か月、`firestore.rules`・`functions`の`SCHEDULED_MAX_DAYS`と同じ31日）。
const int kScheduledMaxDays = 31;

/// 予定の日時として許されるか（未来〜[kScheduledMaxDays]日後）。
bool isScheduledTimeAllowed(DateTime sendAt, DateTime now) {
  return sendAt.isAfter(now) &&
      !sendAt.isAfter(now.add(const Duration(days: kScheduledMaxDays)));
}

/// 1寄合あたり、自分が予定できる未送信の件数の上限。
const int kScheduledMaxPerRoom = 20;
