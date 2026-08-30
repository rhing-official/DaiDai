import 'package:firebase_storage/firebase_storage.dart';

import 'file_extension_policy.dart';

/// アルバムに登録するファイルのFirebase Storage保存先パスを組み立てる。
/// 既存の添付ファイル（`dmFiles/$dmId`、`groupFiles/$groupId`、
/// `lib/utils/attachment_upload.dart`参照）とは衝突しない別prefixにし、
/// 将来実装される画像・動画の期限切れ処理が`dmFiles`/`groupFiles`のみを
/// 対象にする限り、アルバムのファイルは自然に対象外になる。
String albumStoragePath({
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String albumId,
  required String itemId,
  required String extension,
}) {
  final scope = isDm ? 'dm' : 'group';
  return 'albumFiles/$scope/$conversationId/$roomId/$albumId/$itemId.$extension';
}

/// メッセージの添付ファイルをダウンロードし、アルバム用の別パスへ
/// コピーする（再圧縮はしない）。「削除するまで半永久的に保存される」
/// という要件のため、元メッセージのStorageファイルの寿命から独立させる
/// のが目的（2026-08-30追加）。
///
/// [sourceUrl]は元メッセージの`MessageFileMetadata.url`
/// （Firebase StorageのダウンロードURL）。パス命名規則を再構築せず
/// `FirebaseStorage.refFromURL`で直接参照する。
Future<String> copyMessageAttachmentToAlbum({
  required FirebaseStorage storage,
  required String sourceUrl,
  required String destPath,
  required String mimeType,
}) async {
  final sourceRef = storage.refFromURL(sourceUrl);
  final bytes = await sourceRef.getData(kMaxAttachmentSizeBytes);
  if (bytes == null) {
    throw StateError('failed to download source attachment: $sourceUrl');
  }
  final destRef = storage.ref(destPath);
  await destRef.putData(bytes, SettableMetadata(contentType: mimeType));
  return destRef.getDownloadURL();
}

/// アルバムからアイテムを削除する際、コピー済みのStorageファイルも消す。
/// 既にファイルが存在しない場合（二重削除等）は無視する。
Future<void> deleteAlbumFile(
  FirebaseStorage storage,
  String storagePath,
) async {
  try {
    await storage.ref(storagePath).delete();
  } on FirebaseException catch (e) {
    if (e.code != 'object-not-found') rethrow;
  }
}
