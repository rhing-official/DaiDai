import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// 入力欄の下書きに添えたファイルを、他の端末へ同期する為の保存先（2026-11-27）。
/// 保存先は、サーバーの実装を差し替えられるよう、パスで受け渡す。
abstract class DraftFileRepository {
  /// [bytes]を保存し、保存先のパスを返す。
  Future<String> upload({
    required String userId,
    required String conversationId,
    required String roomId,
    required String fileId,
    required Uint8List bytes,
    required String contentType,
  });

  /// [path]のファイルを取得する。失敗（既に消えた等）は`null`。
  Future<Uint8List?> download(String path, int maxBytes);

  /// [path]のファイルを消す。既に無くても、失敗にしない。
  Future<void> delete(String path);
}

class FirebaseDraftFileRepository implements DraftFileRepository {
  FirebaseDraftFileRepository({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> upload({
    required String userId,
    required String conversationId,
    required String roomId,
    required String fileId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = 'draftFiles/$userId/$conversationId/$roomId/$fileId';
    await _storage
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: contentType));
    return path;
  }

  @override
  Future<Uint8List?> download(String path, int maxBytes) async {
    try {
      return await _storage.ref(path).getData(maxBytes);
    } catch (e) {
      debugPrint('[DRAFT-FILE] download failed: $path $e');
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (_) {
      // 既に消えている。
    }
  }
}
