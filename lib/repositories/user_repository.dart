import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/app_user.dart';
import '../models/profile_material.dart';
import '../models/user_invite_preview.dart';

/// idを持つ蔵アイテムのリストから1件だけ検索する（プロフィールカードが
/// 指すニックネーム・アイコンの解決に使う）。
T? _findById<T>(List<T> items, String? id, String Function(T) idOf) {
  if (id == null) return null;
  for (final item in items) {
    if (idOf(item) == id) return item;
  }
  return null;
}

abstract class UserRepository {
  Future<AppUser?> getUser(String userId);

  /// 複数のuserIdからまとめて取得する（広場のメンバー一覧表示などで使う）。
  Future<List<AppUser>> getUsersByIds(List<String> userIds);

  /// 相手のプロフィール（アクティブなニックネームなど）をリアルタイムに購読する。
  Stream<AppUser?> watchUser(String userId);

  Future<void> createUser(AppUser user);
  Future<AppUser?> findByRhingId(String rhingId);
  Future<bool> isRhingIdAvailable(String rhingId);
  Future<void> updateUser(AppUser user);

  /// 蔵の配列フィールド（icons/backgroundImages/statusMessages/nicknames/
  /// profileCards）に1件だけ原子的に追加する。[updateUser]（ローカルで組み立てた
  /// AppUser全体を`.set()`で丸ごと上書き）だと、蔵への追加操作を短時間に
  /// 複数実行した場合（例: アイコンのアップロード中にニックネームを追加するなど）、
  /// 後から完了した書き込みが先に完了した書き込みを消してしまう競合が起きうる。
  /// Firestoreの`arrayUnion`によるフィールド単位の更新はサーバー側でマージされるため、
  /// この種の競合が起きない。
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  );

  /// [addToProfileList]の逆（`arrayRemove`）。
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  );

  /// activeIconId等、単一の値を持つフィールドを原子的に更新する。
  Future<void> setProfileField(String userId, String field, String? value);

  /// 蔵にアイコン画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes);

  /// 蔵に背景画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadBackgroundImage(String userId, Uint8List bytes);

  /// アップロード済み画像素材をStorageから削除する。
  Future<void> deleteProfileMaterial(ProfileMaterial material);

  /// 縁結びの招待リンクを外部SNSで展開（OGP）した時に見せる公開プレビュー
  /// （`userInvites/{rhingId}`）を、現在のアクティブなアイコン・呼び名から
  /// 同期する。蔵の更新時（[addToProfileList]等）に自動で呼ばれるほか、
  /// この機能追加より前から使っているユーザーはその同期がまだ一度も
  /// 走っていないため、縁結びページを開いた際にも呼び直してバックフィルする。
  Future<void> syncInvitePreview(String userId);
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
  Future<List<AppUser>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    // FirestoreのwhereInは1クエリにつき最大30件のため、超える場合は分割する。
    final results = <AppUser>[];
    for (var i = 0; i < userIds.length; i += 30) {
      final chunk = userIds.skip(i).take(30).toList();
      final snapshot = await _users
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snapshot.docs.map((doc) => AppUser.fromJson(doc.data())));
    }
    return results;
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
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    await _users.doc(userId).update({
      field: FieldValue.arrayUnion([value]),
    });
    if (field == 'icons' || field == 'nicknames') {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    await _users.doc(userId).update({
      field: FieldValue.arrayRemove([value]),
    });
    if (field == 'icons' || field == 'nicknames') {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> setProfileField(
    String userId,
    String field,
    String? value,
  ) async {
    await _users.doc(userId).update({field: value});
    if (field == 'activeIconId' ||
        field == 'activeNicknameId' ||
        field == 'activeProfileCardId') {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> syncInvitePreview(String userId) async {
    final user = await getUser(userId);
    if (user == null) return;
    // 工房でプロフィールカードを適用（activeProfileCardId）していれば、
    // そのカードが指す蔵アイテムを優先する。未適用ならこれまで通り
    // 個別の蔵アイテムのactive*から組み立てる。
    final card = user.activeProfileCard;
    final nickname = card != null
        ? _findById(user.nicknames, card.nicknameId, (n) => n.id)?.text
        : user.activeNickname?.text;
    final iconUrl = card != null
        ? _findById(user.icons, card.iconId, (m) => m.id)?.url
        : user.activeIcon?.url;
    final preview = UserInvitePreview(
      userId: user.userId,
      nickname: nickname,
      iconUrl: iconUrl,
    );
    await _firestore
        .collection('userInvites')
        .doc(user.rhingId)
        .set(preview.toJson());
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
