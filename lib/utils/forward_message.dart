import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/message.dart';
import '../providers/repository_providers.dart';
import 'attachment_upload.dart';

/// 転送先の種類。
enum ForwardTargetKind { dm, group }

/// 転送先（一対か広場の、ひとつの寄合、2026-11-05）。
class ForwardTarget {
  const ForwardTarget({
    required this.kind,
    required this.conversationId,
    required this.roomId,
  });

  final ForwardTargetKind kind;

  /// 一対なら`dmId`、広場なら`groupId`。
  final String conversationId;
  final String roomId;
}

/// 転送できるメッセージか。本文・添付・ぺったんだけが対象で、通話履歴・予定や投票などの
/// 通知カード・アカウント削除通知・bot/お便りは対象外。
bool canForwardMessage(Message message) {
  switch (message.contentType) {
    case 'text':
      return message.content.trim().isNotEmpty;
    case 'image':
    case 'video':
    case 'file':
      return message.fileMetadata != null;
    case 'multi':
      return message.attachments.isNotEmpty;
    case 'sticker':
      return message.stickerData != null;
    default:
      return false;
  }
}

/// 元のURLからバイト列を取得する。容量上限を超えるものは[AttachmentTooLargeException]相当として
/// [StateError]で知らせる。
Future<Uint8List> _fetchBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

String _contentTypeOfMime(String mimeType) {
  if (mimeType.startsWith('image/')) return 'image';
  if (mimeType.startsWith('video/')) return 'video';
  return 'file';
}

/// [message]を、[target]へ新しいメッセージとして送る（送信者は[senderId]、返信・メンション・
/// リアクションは引き継がない。「転送」の表示も付けない、2026-11-05）。添付は元のURLから
/// 取得して保存し直す。失敗したら例外を投げる。
Future<void> forwardMessage({
  required WidgetRef ref,
  required Message message,
  required ForwardTarget target,
  required String senderId,
  required String senderRhingSeed,
}) async {
  final isDm = target.kind == ForwardTargetKind.dm;
  final dmRepo = ref.read(directMessageRepositoryProvider);
  final groupRepo = ref.read(groupRepositoryProvider);

  switch (message.contentType) {
    case 'text':
      if (isDm) {
        await dmRepo.sendTextMessage(
          dmId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          content: message.content,
        );
      } else {
        await groupRepo.sendRoomMessage(
          groupId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          content: message.content,
        );
      }
    case 'sticker':
      final sticker = message.stickerData!;
      if (isDm) {
        await dmRepo.sendStickerMessage(
          dmId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          stickerId: sticker.stickerId,
          stickerName: message.content,
          stickerUrl: sticker.stickerUrl,
        );
      } else {
        await groupRepo.sendStickerMessage(
          groupId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          stickerId: sticker.stickerId,
          stickerName: message.content,
          stickerUrl: sticker.stickerUrl,
        );
      }
    case 'multi':
      final items = <AttachmentUploadInput>[];
      for (final a in message.attachments) {
        items.add(
          AttachmentUploadInput(
            bytes: await _fetchBytes(a.url),
            fileName: a.fileName,
            contentType: _contentTypeOfMime(a.mimeType),
          ),
        );
      }
      if (isDm) {
        await dmRepo.sendMultiAttachmentMessage(
          dmId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          items: items,
          caption: message.caption,
        );
      } else {
        await groupRepo.sendMultiAttachmentMessage(
          groupId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          items: items,
          caption: message.caption,
        );
      }
    default:
      final meta = message.fileMetadata!;
      await forwardFile(
        ref: ref,
        url: meta.url,
        fileName: meta.fileName,
        contentType: message.contentType,
        caption: message.caption,
        target: target,
        senderId: senderId,
        senderRhingSeed: senderRhingSeed,
      );
  }
}

/// 添付1件（URL）を[target]へ転送する。拡大表示の転送アイコンからも使う。
Future<void> forwardFile({
  required WidgetRef ref,
  required String url,
  required String fileName,
  required String contentType,
  required ForwardTarget target,
  required String senderId,
  required String senderRhingSeed,
  String? caption,
}) async {
  final bytes = await _fetchBytes(url);
  if (target.kind == ForwardTargetKind.dm) {
    await ref
        .read(directMessageRepositoryProvider)
        .sendAttachmentMessage(
          dmId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          bytes: bytes,
          fileName: fileName,
          contentType: contentType,
          caption: caption,
        );
  } else {
    await ref
        .read(groupRepositoryProvider)
        .sendAttachmentMessage(
          groupId: target.conversationId,
          roomId: target.roomId,
          senderId: senderId,
          senderRhingSeed: senderRhingSeed,
          bytes: bytes,
          fileName: fileName,
          contentType: contentType,
          caption: caption,
        );
  }
}
