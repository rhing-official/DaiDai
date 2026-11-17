import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/soundboard_sound.dart';
import '../utils/sound_upload.dart';

/// サウンドボードの効果音（2026-11-16、2026-11-17に個人保存へ変更）。
///
/// 音は追加した人のアカウントに保存する（マスター`users/{uid}/soundboardSounds`、ファイルは
/// `soundboard/user/{uid}/{soundId}/audio.{拡張子}`）。追加した語らい（広場`groups/{id}`・
/// 一対`directMessages/{id}`、[isDm]＋[conversationId]で指す）には、同じidの参照を置き、
/// その語らいのメンバーが使えるようにする。以前の（語らい単位の）音は、参照だけが残っていて
/// ファイルも語らいの下にある。
abstract class SoundboardRepository {
  /// 語らいに登録されている音（追加した語らいに置かれた参照と、以前の語らい単位の音）。
  Stream<List<SoundboardSound>> watchSounds({
    required bool isDm,
    required String conversationId,
  });

  /// [userId]が追加した音（個人保存のマスター。どの語らいでも使える）。
  Stream<List<SoundboardSound>> watchMySounds(String userId);

  /// [userId]が追加した音の数（上限の判定用）。
  Future<int> countMySounds(String userId);

  /// 効果音を登録する。容量・拡張子・個数の上限を超えたら例外
  /// （[SoundUploadTooLargeException]・[SoundUploadUnsupportedFormatException]・
  /// [SoundboardFullException]）。[limit]は1人あたりの上限（[soundboardLimitFor]）。
  Future<void> addSound({
    required bool isDm,
    required String conversationId,
    required String userId,
    required String name,
    required String fileName,
    required Uint8List bytes,
    required int limit,
    double volume = 1.0,
  });

  /// 名前・音量を変更する（ファイルは変えない）。追加した本人だけ。
  Future<void> updateSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
    String? name,
    double? volume,
  });

  /// 効果音を消す（追加した本人だけ）。
  Future<void> deleteSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
  });

  /// 効果音のファイルを取得する（保存先のパスから）。
  Future<Uint8List?> fetchBytes(SoundboardSound sound);
}

/// 登録数が1人あたりの上限に達している。
class SoundboardFullException implements Exception {
  const SoundboardFullException();
}

class FirestoreSoundboardRepository implements SoundboardRepository {
  FirestoreSoundboardRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> _collection(
    bool isDm,
    String conversationId,
  ) => _firestore
      .collection(isDm ? 'directMessages' : 'groups')
      .doc(conversationId)
      .collection('soundboardSounds');

  CollectionReference<Map<String, dynamic>> _mine(String userId) =>
      _firestore.collection('users').doc(userId).collection('soundboardSounds');

  SoundboardSound _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SoundboardSound(
      soundId: doc.id,
      name: (data['name'] as String?) ?? '',
      storagePath: (data['storagePath'] as String?) ?? '',
      mimeType: (data['mimeType'] as String?) ?? 'audio/mpeg',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      volume: ((data['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
      originId: data['originId'] as String?,
      originIsDm: data['originIsDm'] == true,
    );
  }

  @override
  Stream<List<SoundboardSound>> watchSounds({
    required bool isDm,
    required String conversationId,
  }) {
    return _collection(isDm, conversationId)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) _fromDoc(doc)]);
  }

  @override
  Stream<List<SoundboardSound>> watchMySounds(String userId) {
    return _mine(userId)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) _fromDoc(doc)]);
  }

  @override
  Future<int> countMySounds(String userId) async {
    final count = await _mine(userId).count().get();
    return count.count ?? 0;
  }

  @override
  Future<void> addSound({
    required bool isDm,
    required String conversationId,
    required String userId,
    required String name,
    required String fileName,
    required Uint8List bytes,
    required int limit,
    double volume = 1.0,
  }) async {
    if (bytes.lengthInBytes > kMaxSoundboardSoundBytes) {
      throw const SoundUploadTooLargeException();
    }
    final extension = soundExtensionOf(fileName);
    if (!kAllowedSoundExtensions.contains(extension)) {
      throw const SoundUploadUnsupportedFormatException();
    }
    if (await countMySounds(userId) >= limit) {
      throw const SoundboardFullException();
    }
    final master = _mine(userId).doc();
    final mimeType = soundMimeTypeFor(extension);
    final path =
        '$kPersonalSoundPathPrefix$userId/${master.id}/audio.$extension';
    await _storage
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: mimeType));
    final data = <String, dynamic>{
      'name': name,
      'storagePath': path,
      'mimeType': mimeType,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'volume': volume.clamp(0.0, 1.0),
      'originIsDm': isDm,
      'originId': conversationId,
    };
    // マスター（本人のどの語らいでも使う）と、追加した語らいの参照（そのメンバーが使う）を
    // 同じバッチで作る。
    final batch = _firestore.batch();
    batch.set(master, data);
    batch.set(_collection(isDm, conversationId).doc(master.id), data);
    await batch.commit();
  }

  @override
  Future<void> updateSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
    String? name,
    double? volume,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) {
      data['name'] = String.fromCharCodes(
        name.trim().runes.take(kMaxSoundboardNameLength),
      );
    }
    if (volume != null) data['volume'] = volume.clamp(0.0, 1.0);
    if (data.isEmpty) return;
    if (!sound.isPersonal) {
      // 以前の（語らい単位の）音。
      await _collection(isDm, conversationId).doc(sound.soundId).update(data);
      return;
    }
    await _mine(sound.createdBy).doc(sound.soundId).update(data);
    await _updateReference(sound, data);
  }

  /// 追加した語らいの参照を更新する。その語らいが無くなっていても（絶縁・広場の削除など）、
  /// 本人の音は変更できるよう、失敗は無視する。
  Future<void> _updateReference(
    SoundboardSound sound,
    Map<String, dynamic> data,
  ) async {
    final originId = sound.originId;
    if (originId == null) return;
    try {
      await _collection(
        sound.originIsDm,
        originId,
      ).doc(sound.soundId).update(data);
    } catch (_) {
      // 参照が既に無い。
    }
  }

  @override
  Future<void> deleteSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
  }) async {
    if (sound.isPersonal) {
      await _mine(sound.createdBy).doc(sound.soundId).delete();
      final originId = sound.originId;
      if (originId != null) {
        try {
          await _collection(
            sound.originIsDm,
            originId,
          ).doc(sound.soundId).delete();
        } catch (_) {
          // 参照が既に無い（語らいが無くなった等）。
        }
      }
    } else {
      await _collection(isDm, conversationId).doc(sound.soundId).delete();
    }
    try {
      await _storage.ref(sound.storagePath).delete();
    } catch (_) {
      // ファイルが既に無い等。一覧からは消えているので続行する。
    }
  }

  @override
  Future<Uint8List?> fetchBytes(SoundboardSound sound) {
    return _storage.ref(sound.storagePath).getData(kMaxSoundboardSoundBytes);
  }
}
