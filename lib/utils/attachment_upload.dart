import 'dart:io' show Platform;
import 'dart:math' as math;
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

  // 動画が画像として渡された場合（ピッカーが種別を誤判定した時）の保険。
  // そのまま画像として保存すると、壊れた画像になり再生もできない。
  final kind = contentType == 'image' && looksLikeVideoBytes(bytes)
      ? 'video'
      : contentType;

  var uploadBytes = bytes;
  var extension = _extensionOf(fileName);
  var mimeType = _guessMimeType(extension, kind);
  String? compressionType;

  if (kind == 'image') {
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
  final task = ref.putData(
    uploadBytes,
    SettableMetadata(contentType: mimeType),
  );
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

const _videoExtensions = {
  'mp4',
  'mov',
  'm4v',
  'webm',
  'mkv',
  'avi',
  '3gp',
  '3g2',
  'mts',
  'm2ts',
  'wmv',
  'flv',
  'ogv',
};

/// `ImagePicker().pickMedia()`/`pickMultipleMedia()`のように画像・動画いずれかを
/// 返すピッカーから得た`XFile`が動画かどうかを判定する（2026-09-26追加、
/// 2026-10-16に堅牢化）。`mimeType`が`video/`・`image/`で始まる場合だけそれを
/// 信じ、null・空・`application/octet-stream`等の当てにならない値の時は拡張子で
/// 判定する（Webでは空文字等が返り、動画が画像として送られていた）。
bool isVideoFileName(String fileName, {String? mimeType}) {
  if (mimeType != null) {
    if (mimeType.startsWith('video/')) return true;
    if (mimeType.startsWith('image/')) return false;
  }
  return _videoExtensions.contains(_extensionOf(fileName));
}

/// ファイル先頭のバイト列から動画かどうかを判定する（拡張子・MIMEが当てに
/// ならない時の最終手段、2026-10-16追加）。ISO BMFF（mp4・mov・3gp等）は
/// 4〜11バイト目の`ftyp`＋ブランド、webm/mkvはEBMLヘッダー、aviは
/// `RIFF....AVI `。HEIC/AVIFもISO BMFFだがブランドが違うため画像として除く。
bool looksLikeVideoBytes(Uint8List bytes) {
  if (bytes.length < 12) return false;
  String ascii(int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));
  if (ascii(4, 8) == 'ftyp') {
    final brand = ascii(8, 12);
    const videoBrands = {
      'isom',
      'iso2',
      'iso4',
      'iso5',
      'iso6',
      'mp41',
      'mp42',
      'avc1',
      'M4V ',
      'M4VH',
      'M4VP',
      'qt  ',
      'dash',
      'MSNV',
    };
    return videoBrands.contains(brand) ||
        brand.startsWith('3gp') ||
        brand.startsWith('3g2');
  }
  if (bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3) {
    return true;
  }
  return ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'AVI ';
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

/// [uploadMultiMessageAttachments]へ渡す1件分の入力（2026-10-16追加）。
class AttachmentUploadInput {
  const AttachmentUploadInput({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;

  /// file | image | video
  final String contentType;
}

/// 複数の添付を1つのメッセージ分まとめてアップロードする（2026-10-16追加）。
/// 各ファイルは`$storagePathPrefix/$messageId/$index.<ext>`へ保存し、同時に
/// [concurrency]件ずつ送る。進捗は全体の平均で[onProgress]へ流す。
///
/// 1件でも失敗したら、残りの開始を止め、アップロード済みのファイルを全て
/// 削除した上で最初のエラーをそのまま投げる（部分的に送られたメッセージを
/// 作らないため）。成功時は入力と同じ順序のメタデータを返す。
Future<List<MessageFileMetadata>> uploadMultiMessageAttachments({
  required FirebaseStorage storage,
  required String storagePathPrefix,
  required String messageId,
  required List<AttachmentUploadInput> items,
  ValueChanged<double>? onProgress,
  int concurrency = 3,
}) async {
  final results = List<MessageFileMetadata?>.filled(items.length, null);
  final progress = List<double>.filled(items.length, 0);
  void report() {
    if (items.isEmpty) return;
    onProgress?.call(progress.fold<double>(0, (a, b) => a + b) / items.length);
  }

  Object? failure;
  StackTrace? failureStack;
  var next = 0;

  Future<void> worker() async {
    while (failure == null) {
      final index = next++;
      if (index >= items.length) return;
      final item = items[index];
      try {
        results[index] = await uploadMessageAttachment(
          storage: storage,
          storagePathPrefix: storagePathPrefix,
          attachmentId: '$messageId/$index',
          bytes: item.bytes,
          fileName: item.fileName,
          contentType: item.contentType,
          onProgress: (p) {
            progress[index] = p;
            report();
          },
        );
        progress[index] = 1;
        report();
      } catch (e, st) {
        failure ??= e;
        failureStack ??= st;
      }
    }
  }

  await Future.wait([
    for (var w = 0; w < math.min(concurrency, items.length); w++) worker(),
  ]);

  final error = failure;
  if (error != null) {
    await Future.wait([
      for (final uploaded in results.whereType<MessageFileMetadata>())
        storage.refFromURL(uploaded.url).delete().catchError((_) {}),
    ]);
    Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
  }
  return results.cast<MessageFileMetadata>();
}

/// `contentType='multi'`のメッセージの`content`（返信スニペット・コピー等の
/// 既存処理がそのまま使える代替文字列）。添付名を` / `で連結する。
String multiAttachmentContent(List<MessageFileMetadata> attachments) =>
    attachments.map((a) => a.fileName).join(' / ');

/// メッセージのFirestoreデータに含まれる添付ファイルのStorage URLを全て返す
/// （単一添付の`fileMetadata`と、複数添付の`attachments`。重複は除く）。
/// 物理削除時にStorage上の実体もまとめて消すために使う（2026-10-16）。
Set<String> attachmentUrlsOfMessageData(Map<String, dynamic>? data) {
  final urls = <String>{};
  final single = (data?['fileMetadata'] as Map?)?['url'];
  if (single is String) urls.add(single);
  for (final item in (data?['attachments'] as List?) ?? const []) {
    final url = (item as Map?)?['url'];
    if (url is String) urls.add(url);
  }
  return urls;
}
