import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show ValueChanged, kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/message.dart';
import 'file_extension_policy.dart';
import 'image_format.dart';

/// 容量上限（[kMaxAttachmentSizeBytes]）超過。呼び出し元（UIの
/// `_handleAttachmentPicked`）が`Strings.chatAttachmentTooLargeMessage`を
/// 出し分けるための専用型（メッセージ文字列で判定させないため）。
class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException();
}

/// 拡張子ブロックリストによる拒否。呼び出し元が
/// `Strings.chatAttachmentBlockedExtensionMessage`を出し分けるための専用型。
class AttachmentExtensionBlockedException implements Exception {
  const AttachmentExtensionBlockedException();
}

/// メッセージへのファイル・画像・動画添付を検証してFirebase Storageへ
/// アップロードする共通処理（`DirectMessageRepository`/`GroupRepository`の
/// `sendAttachmentMessage`実装から共有、技術仕様書5.2参照、2026-08-10追加）。
///
/// [storagePathPrefix]は呼び出し元が会話種別ごとに決める保存先
/// （一対=`dmFiles/$dmId`、広場=`groupFiles/$groupId`。storage.rulesの
/// 権限判定がこのパス上のトップレベルセグメントを参照するため、
/// 会話をまたいで衝突しない値にすること）。[attachmentId]はメッセージid
/// （呼び出し元が事前に採番した`messageRef.id`）をそのまま使う想定。
///
/// [contentType]はfile|image|videoのいずれか。画像のみWebP圧縮を試みる
/// （GIF・圧縮失敗時は元のバイトのまま、`user_repository.dart`の蔵
/// アップロードと同じ方針）。ファイルのみ拡張子ブロックリストを適用する
/// （画像・動画は形式チェックのみで拡張子では弾かない）。
Future<MessageFileMetadata> uploadMessageAttachment({
  required FirebaseStorage storage,
  required String storagePathPrefix,
  required String attachmentId,
  required Uint8List bytes,
  required String fileName,
  required String contentType,
  ValueChanged<double>? onProgress,
}) async {
  if (bytes.lengthInBytes > kMaxAttachmentSizeBytes) {
    throw const AttachmentTooLargeException();
  }
  if (contentType == 'file' && isBlockedFileExtension(fileName)) {
    throw const AttachmentExtensionBlockedException();
  }

  var uploadBytes = bytes;
  var extension = _extensionOf(fileName);
  var mimeType = _guessMimeType(extension, contentType);
  String? compressionType;

  if (contentType == 'image') {
    final isGif = isGifBytes(bytes);
    final compressed = isGif
        ? null
        : await _tryCompressMessageImageToWebp(bytes);
    if (isGif) {
      extension = 'gif';
      mimeType = 'image/gif';
      compressionType = 'raw';
    } else if (compressed != null) {
      uploadBytes = compressed;
      extension = 'webp';
      mimeType = 'image/webp';
      compressionType = 'webp';
    } else {
      final format = rawUploadFormatFor(bytes);
      extension = format.extension;
      mimeType = format.contentType;
      compressionType = 'raw';
    }
  }

  final path = '$storagePathPrefix/$attachmentId.$extension';
  final ref = storage.ref(path);
  final task = ref.putData(uploadBytes, SettableMetadata(contentType: mimeType));
  if (onProgress != null) {
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
  }
  await task;
  final url = await ref.getDownloadURL();

  return MessageFileMetadata(
    url: url,
    fileName: fileName,
    extension: extension,
    sizeBytes: uploadBytes.lengthInBytes,
    mimeType: mimeType,
    compressionType: compressionType,
  );
}

String _extensionOf(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
  return fileName.substring(dotIndex + 1).toLowerCase();
}

const Map<String, String> _mimeTypesByExtension = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
};

String _guessMimeType(String extension, String contentType) {
  final known = _mimeTypesByExtension[extension];
  if (known != null) return known;
  if (contentType == 'video') return 'video/mp4';
  return 'application/octet-stream';
}

/// flutter_image_compressはWindows/Linuxを未対応のため、その場合や圧縮に
/// 失敗した場合はnullを返す（呼び出し元は元のバイトのままアップロードする、
/// `user_repository.dart`/`group_repository.dart`の同様の処理を参照）。
/// メッセージ添付の写真はアイコンより大きく表示されるため、蔵アイコン
/// （512px）より広めの1600pxを上限にする。
Future<Uint8List?> _tryCompressMessageImageToWebp(Uint8List bytes) async {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return null;
  try {
    return await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 85,
      format: CompressFormat.webp,
    );
  } catch (_) {
    return null;
  }
}
