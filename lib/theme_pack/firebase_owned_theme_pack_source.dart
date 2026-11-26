import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'owned_theme_pack_repository.dart';

/// 取得済みの意匠の、Firebaseでの置き場（`users/{uid}/ownedThemePacks`・`themePacks`・Storage）。
class FirebaseOwnedThemePackSource implements OwnedThemePackSource {
  FirebaseOwnedThemePackSource({
    required this.userId,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final String userId;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  @override
  Future<List<OwnedThemePackRecord>> listOwned() async {
    final snap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('ownedThemePacks')
        .get();
    return [
      for (final d in snap.docs)
        if (d.data()['version'] is num)
          OwnedThemePackRecord(
            packId: d.id,
            version: (d.data()['version'] as num).toInt(),
          ),
    ];
  }

  @override
  Future<PublishedThemePack?> published(String packId) async {
    final doc = await _firestore.collection('themePacks').doc(packId).get();
    final data = doc.data();
    if (data == null) return null;
    return PublishedThemePack(
      name: data['name'] as String? ?? packId,
      version: (data['version'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'approved',
    );
  }

  @override
  Future<Uint8List> readFile(String path, int maxBytes) async {
    final data = await _storage.ref(path).getData(maxBytes);
    if (data == null) throw StateError('empty');
    return data;
  }
}
