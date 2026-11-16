import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/soundboard_sound.dart';
import '../utils/sound_upload.dart';

/// サウンドボードの効果音（2026-11-16）。広場（`groups/{id}`）・一対
/// （`directMessages/{id}`）のどちらも、[isDm]＋[conversationId]で指す。
abstract class SoundboardRepository {
  Stream<List<SoundboardSound>> watchSounds({
    required bool isDm,
    required String conversationId,
  });

  /// 効果音を登録する。容量・拡張子・個数の上限を超えたら例外
  /// （[SoundUploadTooLargeException]・[SoundUploadUnsupportedFormatException]・
  /// [SoundboardFullException]）。
  Future<void> addSound({
    required bool isDm,
    required String conversationId,
    required String userId,
    required String name,
    required String fileName,
    required Uint8List bytes,
    double volume = 1.0,
  });

  /// 名前・音量を変更する（ファイルは変えない）。
  Future<void> updateSound({
    required bool isDm,
    required String conversationId,
    required String soundId,
    String? name,
    double? volume,
  });

  Future<void> deleteSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
  });

  /// 効果音のファイルを取得する（保存先のパスから）。
  Future<Uint8List?> fetchBytes(SoundboardSound sound);
}

/// 登録数が[kMaxSoundboardSounds]に達している。
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

  @override
  Stream<List<SoundboardSound>> watchSounds({
    required bool isDm,
    required String conversationId,
  }) {
    return _collection(
      isDm,
      conversationId,
    ).orderBy('createdAt').snapshots().map((snapshot) {
      return [
        for (final doc in snapshot.docs)
          SoundboardSound(
            soundId: doc.id,
            name: (doc.data()['name'] as String?) ?? '',
            storagePath: (doc.data()['storagePath'] as String?) ?? '',
            mimeType: (doc.data()['mimeType'] as String?) ?? 'audio/mpeg',
            createdBy: (doc.data()['createdBy'] as String?) ?? '',
            createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
            volume: ((doc.data()['volume'] as num?)?.toDouble() ?? 1.0).clamp(
              0.0,
              1.0,
            ),
          ),
      ];
    });
  }

  @override
  Future<void> addSound({
    required bool isDm,
    required String conversationId,
    required String userId,
    required String name,
    required String fileName,
    required Uint8List bytes,
    double volume = 1.0,
  }) async {
    if (bytes.lengthInBytes > kMaxSoundboardSoundBytes) {
      throw const SoundUploadTooLargeException();
    }
    final extension = soundExtensionOf(fileName);
    if (!kAllowedSoundExtensions.contains(extension)) {
      throw const SoundUploadUnsupportedFormatException();
    }
    final collection = _collection(isDm, conversationId);
    final count = await collection.count().get();
    if ((count.count ?? 0) >= kMaxSoundboardSounds) {
      throw const SoundboardFullException();
    }
    final doc = collection.doc();
    final mimeType = soundMimeTypeFor(extension);
    final path =
        'soundboard/${isDm ? 'dm' : 'group'}/$conversationId/${doc.id}.$extension';
    await _storage
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: mimeType));
    await doc.set({
      'name': name,
      'storagePath': path,
      'mimeType': mimeType,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'volume': volume.clamp(0.0, 1.0),
    });
  }

  @override
  Future<void> updateSound({
    required bool isDm,
    required String conversationId,
    required String soundId,
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
    await _collection(isDm, conversationId).doc(soundId).update(data);
  }

  @override
  Future<void> deleteSound({
    required bool isDm,
    required String conversationId,
    required SoundboardSound sound,
  }) async {
    await _collection(isDm, conversationId).doc(sound.soundId).delete();
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
