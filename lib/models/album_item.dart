import 'package:cloud_firestore/cloud_firestore.dart';

/// アルバムに登録された画像・動画1件（`.../albums/{albumId}/items/{itemId}`、
/// 2026-08-30追加）。
///
/// [Message.fileMetadata]（`lib/models/message.dart`の`MessageFileMetadata`）
/// とフィールド構成は近いが、元メッセージが削除・期限切れで消えた後も
/// 独立して存在し続ける必要があるため、あえて別クラスにしている。
/// 元ファイルは登録時にコピーして[storagePath]/[url]に独自保存する
/// （`lib/utils/album_storage.dart`参照）。
class AlbumItem {
  const AlbumItem({
    required this.itemId,
    required this.contentType,
    required this.storagePath,
    required this.url,
    required this.mimeType,
    required this.extension,
    required this.sizeBytes,
    this.compressionType,
    required this.addedBy,
    this.addedAt,
    this.sourceMessageId,
    this.sourceSenderId,
    this.sourceSentAt,
  });

  final String itemId;

  /// image|video。
  final String contentType;

  /// Firebase Storage上の実パス（`albumFiles/dm/...`または
  /// `albumFiles/group/...`）。削除時にこのパスのファイルを消す。
  final String storagePath;

  /// Firebase StorageのダウンロードURL。
  final String url;

  final String mimeType;
  final String extension;
  final int sizeBytes;

  /// 画像のみ設定（webp|lossless|raw）。動画はnull。
  final String? compressionType;

  final String addedBy;
  final Timestamp? addedAt;

  /// 元メッセージへの参照（任意、由来の記録用。元メッセージが削除
  /// されてもこのアイテム自体には影響しない）。
  final String? sourceMessageId;
  final String? sourceSenderId;
  final Timestamp? sourceSentAt;

  factory AlbumItem.fromJson(String itemId, Map<String, dynamic> json) {
    return AlbumItem(
      itemId: itemId,
      contentType: json['contentType'] as String,
      storagePath: json['storagePath'] as String,
      url: json['url'] as String,
      mimeType: json['mimeType'] as String,
      extension: json['extension'] as String,
      sizeBytes: json['sizeBytes'] as int,
      compressionType: json['compressionType'] as String?,
      addedBy: json['addedBy'] as String,
      addedAt: json['addedAt'] as Timestamp?,
      sourceMessageId: json['sourceMessageId'] as String?,
      sourceSenderId: json['sourceSenderId'] as String?,
      sourceSentAt: json['sourceSentAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'contentType': contentType,
    'storagePath': storagePath,
    'url': url,
    'mimeType': mimeType,
    'extension': extension,
    'sizeBytes': sizeBytes,
    'compressionType': compressionType,
    'addedBy': addedBy,
    'addedAt': addedAt ?? FieldValue.serverTimestamp(),
    'sourceMessageId': sourceMessageId,
    'sourceSenderId': sourceSenderId,
    'sourceSentAt': sourceSentAt,
  };
}
