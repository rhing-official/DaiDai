import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
    final path = 'profileMaterials/$userId/$folder/$id.jpg';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    return ProfileMaterial(id: id, url: url, storagePath: path);
  }

  @override
  Future<void> deleteProfileMaterial(ProfileMaterial material) async {
    await _storage.ref(material.storagePath).delete();
  }
}
