import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/app_user.dart';
import '../models/profile_material.dart';

abstract class UserRepository {
  Future<AppUser?> getUser(String userId);

  /// 相手のプロフィール（アクティブなニックネームなど）をリアルタイムに購読する。
  Stream<AppUser?> watchUser(String userId);

  Future<void> createUser(AppUser user);
  Future<AppUser?> findByRhingId(String rhingId);
  Future<bool> isRhingIdAvailable(String rhingId);
  Future<void> updateUser(AppUser user);

  /// 蔵にアイコン画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes);

  /// 蔵に背景画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadBackgroundImage(String userId, Uint8List bytes);

  /// アップロード済み画像素材をStorageから削除する。
  Future<void> deleteProfileMaterial(ProfileMaterial material);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<AppUser?> getUser(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    return AppUser.fromJson(doc.data()!);
  }

  @override
  Stream<AppUser?> watchUser(String userId) {
    return _users
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromJson(doc.data()!) : null);
  }

  @override
  Future<void> createUser(AppUser user) async {
    await _users.doc(user.userId).set(user.toJson());
  }

  @override
  Future<void> updateUser(AppUser user) async {
    await _users.doc(user.userId).set(user.toJson());
  }

  @override
  Future<AppUser?> findByRhingId(String rhingId) async {
    final snapshot = await _users
        .where('rhingId', isEqualTo: rhingId.toLowerCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return AppUser.fromJson(snapshot.docs.first.data());
  }

  @override
  Future<bool> isRhingIdAvailable(String rhingId) async {
    final snapshot = await _users
        .where('rhingId', isEqualTo: rhingId.toLowerCase())
        .limit(1)
        .get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes) {
    return _uploadMaterial(userId: userId, folder: 'icons', bytes: bytes);
  }

  @override
  Future<ProfileMaterial> uploadBackgroundImage(
    String userId,
    Uint8List bytes,
  ) {
    return _uploadMaterial(
      userId: userId,
      folder: 'backgroundImages',
      bytes: bytes,
    );
  }

  Future<ProfileMaterial> _uploadMaterial({
    required String userId,
    required String folder,
    required Uint8List bytes,
  }) async {
    final id = _users.doc().id;
    // image_pickerはリサイズ・圧縮をせず、カメラ由来の数MB〜10MB超の生バイトを
    // そのまま返すことがある。蔵のサムネイルは72〜128px程度でしか表示しない上、
    // 巨大なJPEGのままだと読み込みが極端に遅く「真っ白」に見える一因になっていた
    // ため、WebPへの圧縮・リサイズを行う（CLAUDE.md記載の画像圧縮方針）。
    // flutter_image_compressはWindows/Linuxを未対応のため、その場合や
    // 何らかの理由で圧縮に失敗した場合は元のバイトのままアップロードする
    // （圧縮失敗でアップロード自体をブロックしないためのフォールバック）。
    final compressed = await _tryCompressToWebp(bytes, folder: folder);
    final extension = compressed != null ? 'webp' : 'jpg';
    final contentType = compressed != null ? 'image/webp' : 'image/jpeg';
    final path = 'profileMaterials/$userId/$folder/$id.$extension';
    final ref = _storage.ref(path);
    await ref.putData(
      compressed ?? bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return ProfileMaterial(id: id, url: url, storagePath: path);
  }

  Future<Uint8List?> _tryCompressToWebp(
    Uint8List bytes, {
    required String folder,
  }) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return null;
    final isIcon = folder == 'icons';
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: isIcon ? 512 : 1080,
        minHeight: isIcon ? 512 : 1080,
        quality: isIcon ? 85 : 80,
        format: CompressFormat.webp,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteProfileMaterial(ProfileMaterial material) async {
    await _storage.ref(material.storagePath).delete();
  }
}
