import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import '../models/scheduled_message.dart';

/// メッセージを今すぐ送る（[sendAt]がnull）か、送信予定として保存する（2026-11-10追加）。
///
/// 今すぐ: `messages`へ書き、寄合と会話本体の最終メッセージの控えを更新する（従来どおり）。
/// 予定: 同じ内容を`scheduledMessages`へ保存するだけ。時刻になるとCloud Functions
/// （`sendScheduledMessages`）が同じ書き込みを行う（メッセージIDは先に確保したものを使う）。
Future<void> commitOrScheduleMessage({
  required FirebaseFirestore firestore,
  required DateTime? sendAt,
  required String scope,
  required String conversationId,
  required String roomId,
  required DocumentReference<Map<String, dynamic>> roomRef,
  required DocumentReference<Map<String, dynamic>> conversationRef,
  required DocumentReference<Map<String, dynamic>> messageRef,
  required Message message,
  required String senderId,
  required String lastMessageContentType,
  String? lastMessagePreview,
}) async {
  if (sendAt != null) {
    if (!isScheduledTimeAllowed(sendAt, DateTime.now())) {
      throw ArgumentError.value(sendAt, 'sendAt', '予定の日時が範囲外です');
    }
    await firestore
        .collection('scheduledMessages')
        .add(
          ScheduledMessage.toCreateJson(
            scope: scope,
            conversationId: conversationId,
            roomId: roomId,
            messageId: messageRef.id,
            message: message.toJson(),
            createdBy: senderId,
            sendAt: sendAt,
            lastMessageContentType: lastMessageContentType,
            lastMessagePreview: lastMessagePreview,
          ),
        );
    return;
  }
  final batch = firestore.batch();
  batch.set(messageRef, message.toJson());
  batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
  batch.update(conversationRef, {
    'lastMessageAt': FieldValue.serverTimestamp(),
    'lastMessageSenderId': senderId,
    'lastMessageContentType': lastMessageContentType,
    'lastMessagePreview': lastMessagePreview,
  });
  await batch.commit();
}
