import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/album.dart';
import '../models/album_item.dart';
import '../models/message.dart';
import '../utils/album_storage.dart';
import '../utils/attachment_upload.dart';

/// 寄合単位の共有アルバム機能のRepository（2026-08-30追加）。
///
/// 一対・広場どちらの寄合でも使う共通インターフェース。`DirectMessageRepository`/
/// `GroupRepository`が持つDM/広場固有の複雑な概念（絶縁・権限ロール等）には
/// 依存せず、「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した
/// 薄い実装にしている。操作権限は寄合の全メンバーが対等（firestore.rules側も
/// `manageRooms`等の広場権限とは連動させない）。
abstract class AlbumRepository {
  Stream<List<Album>> watchAlbums({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  Future<Album> createAlbum({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String name,
    required String createdBy,
  });

  /// アルバム自体と、中の全アイテム（Firestoreドキュメント＋Storageファイル）
  /// を削除する。
  Future<void> deleteAlbum({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  });

  Stream<List<AlbumItem>> watchItems({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  });

  /// 画像・動画メッセージをアルバムに登録する。元ファイルをコピーして
  /// 独立保存するため、[message]の`fileMetadata`がnullの場合や
  /// `contentType`が`image`/`video`以外の場合は[ArgumentError]を投げる。
  Future<AlbumItem> addItemFromMessage({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required Message message,
    required String addedBy,
  });

  /// 端末のギャラリーから選んだ画像・動画をアルバムへ直接アップロードして
  /// 登録する（2026-09-07追加、`AlbumPaneView`の「＋」ボタン用。既存メッセージ
  /// の添付をコピーする[addItemFromMessage]とは異なり、元メッセージを持たない
  /// 新規ファイルが対象）。[contentType]は`image`|`video`のみ対応。
  Future<AlbumItem> addItemFromUpload({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String addedBy,
  });

  /// アルバムからアイテムを削除する（Firestoreドキュメント＋Storageファイル
  /// の両方）。
  Future<void> removeItem({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required String itemId,
  });
}

class FirestoreAlbumRepository implements AlbumRepository {
  FirestoreAlbumRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> _roomsCollection(
    bool isDm,
    String conversationId,
  ) {
    final topLevel = isDm ? 'directMessages' : 'groups';
    return _firestore
        .collection(topLevel)
        .doc(conversationId)
        .collection('rooms');
  }

  CollectionReference<Map<String, dynamic>> _albumsCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).collection('albums');
  }

  DocumentReference<Map<String, dynamic>> _albumRef({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  }) {
    return _albumsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(albumId);
  }

  CollectionReference<Map<String, dynamic>> _itemsCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  }) {
    return _albumRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).collection('items');
  }

  @override
  Stream<List<Album>> watchAlbums({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    // messagesサブコレクションの既存クエリ（DirectMessageRepository.
    // watchMessages等）と同じく、where句を付けなくてもfirestore.rulesは
    // 親roomドキュメントをget()して判定するため`list`権限の問題は起きない
    // （`rooms`コレクション自体のwatchRoomsとは事情が異なる、
    // 2026-07-29に発覚した既存の教訓を踏まえた設計）。
    return _albumsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      final albums =
          snapshot.docs
              .map((doc) => Album.fromJson(doc.id, doc.data()))
              .toList()
            ..sort(
              (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
                a.createdAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
      return albums;
    });
  }

  @override
  Future<Album> createAlbum({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String name,
    required String createdBy,
  }) async {
    final ref = _albumsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final album = Album(
      albumId: ref.id,
      roomId: roomId,
      name: name,
      createdBy: createdBy,
    );
    await ref.set(album.toJson());
    return album;
  }

  @override
  Future<void> deleteAlbum({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  }) async {
    final itemsRef = _itemsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    );
    final itemsSnapshot = await itemsRef.get();
    for (final doc in itemsSnapshot.docs) {
      final item = AlbumItem.fromJson(doc.id, doc.data());
      await deleteAlbumFile(_storage, item.storagePath);
    }
    final batch = _firestore.batch();
    for (final doc in itemsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(
      _albumRef(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        albumId: albumId,
      ),
    );
    await batch.commit();
  }

  @override
  Stream<List<AlbumItem>> watchItems({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  }) {
    return _itemsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).snapshots().map((snapshot) {
      final items =
          snapshot.docs
              .map((doc) => AlbumItem.fromJson(doc.id, doc.data()))
              .toList()
            ..sort(
              (a, b) => (b.addedAt?.millisecondsSinceEpoch ?? 0).compareTo(
                a.addedAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
      return items;
    });
  }

  @override
  Future<AlbumItem> addItemFromMessage({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required Message message,
    required String addedBy,
  }) async {
    final fileMetadata = message.fileMetadata;
    if (fileMetadata == null ||
        (message.contentType != 'image' && message.contentType != 'video')) {
      throw ArgumentError(
        'message ${message.messageId} is not an image/video attachment',
      );
    }

    final itemRef = _itemsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).doc();
    final destPath = albumStoragePath(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
      itemId: itemRef.id,
      extension: fileMetadata.extension,
    );
    final copiedUrl = await copyMessageAttachmentToAlbum(
      storage: _storage,
      sourceUrl: fileMetadata.url,
      destPath: destPath,
      mimeType: fileMetadata.mimeType,
    );

    final item = AlbumItem(
      itemId: itemRef.id,
      contentType: message.contentType,
      storagePath: destPath,
      url: copiedUrl,
      mimeType: fileMetadata.mimeType,
      extension: fileMetadata.extension,
      sizeBytes: fileMetadata.sizeBytes,
      compressionType: fileMetadata.compressionType,
      addedBy: addedBy,
      sourceMessageId: message.messageId,
      sourceSenderId: message.senderId,
      sourceSentAt: message.sentAt,
    );

    await _commitNewItem(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
      itemRef: itemRef,
      item: item,
    );
    return item;
  }

  @override
  Future<AlbumItem> addItemFromUpload({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String addedBy,
  }) async {
    final itemRef = _itemsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).doc();
    final scope = isDm ? 'dm' : 'group';
    final storagePathPrefix =
        'albumFiles/$scope/$conversationId/$roomId/$albumId';
    final fileMetadata = await uploadMessageAttachment(
      storage: _storage,
      storagePathPrefix: storagePathPrefix,
      attachmentId: itemRef.id,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );

    final item = AlbumItem(
      itemId: itemRef.id,
      contentType: contentType,
      storagePath: '$storagePathPrefix/${itemRef.id}.${fileMetadata.extension}',
      url: fileMetadata.url,
      mimeType: fileMetadata.mimeType,
      extension: fileMetadata.extension,
      sizeBytes: fileMetadata.sizeBytes,
      compressionType: fileMetadata.compressionType,
      addedBy: addedBy,
    );

    await _commitNewItem(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
      itemRef: itemRef,
      item: item,
    );
    return item;
  }

  /// アイテムドキュメントの追加＋アルバムの非正規化カバー情報の更新を
  /// バッチで行う共通処理（[addItemFromMessage]/[addItemFromUpload]が
  /// アイテムの取得元だけを変えて共有する、2026-09-07切り出し）。
  Future<void> _commitNewItem({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required DocumentReference<Map<String, dynamic>> itemRef,
    required AlbumItem item,
  }) {
    final albumRef = _albumRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    );
    final batch = _firestore.batch();
    batch.set(itemRef, item.toJson());
    batch.update(albumRef, {
      'itemCount': FieldValue.increment(1),
      'coverItemId': item.itemId,
      'coverThumbnailUrl': item.url,
      'coverContentType': item.contentType,
    });
    return batch.commit();
  }

  @override
  Future<void> removeItem({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required String itemId,
  }) async {
    final itemRef = _itemsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).doc(itemId);
    final doc = await itemRef.get();
    if (!doc.exists) return;
    final item = AlbumItem.fromJson(doc.id, doc.data()!);
    await deleteAlbumFile(_storage, item.storagePath);
    await itemRef.delete();
    // カバーの再計算は行わない（次にアイテムを追加した時点で最新の
    // ものに上書きされる、一覧表示用の非正規化キャッシュのため厳密さは
    // 求めない）。
    await _albumRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      albumId: albumId,
    ).update({'itemCount': FieldValue.increment(-1)});
  }
}
