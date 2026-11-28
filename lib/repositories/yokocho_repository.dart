import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/creator_profile.dart';
import '../models/sticker.dart';
import '../services/app_functions.dart';

/// daidai横丁（ぺったんの閲覧・所持・お気に入り・カート）を扱うRepository（2026-11-28）。
/// UIからFirestoreを直接叩かず、ここを通す。購入・出品・審査は扱わず、ブラウザの横丁に任せる。
abstract class YokochoRepository {
  /// 公開中のぺったんの一覧。新しい順。
  Stream<List<StickerPack>> watchCatalog();

  /// [creatorIds]の公開プロフィール。出品者のいない・読めないものは含めない。
  Future<Map<String, CreatorProfile>> loadCreators(Iterable<String> creatorIds);

  /// [userId]が所持しているぺったんのid。
  Stream<Set<String>> watchOwnedIds(String userId);

  /// [userId]のお気に入りのぺったんのid。
  Stream<Set<String>> watchFavouriteIds(String userId);

  /// [userId]のカートのぺったんのid。
  Stream<Set<String>> watchCartIds(String userId);

  Future<void> setFavourite(String userId, String packId, {required bool on});

  Future<void> setCart(String userId, String packId, {required bool on});

  /// 無料のぺったんを入手する。有料は対象外で、既に持っていれば何もしない。
  Future<void> acquireFree(String packId);
}

class FirestoreYokochoRepository implements YokochoRepository {
  FirestoreYokochoRepository({
    FirebaseFirestore? firestore,
    AppFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? AppFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final AppFunctions _functions;

  CollectionReference<Map<String, dynamic>> _userCollection(
    String userId,
    String name,
  ) => _firestore.collection('users').doc(userId).collection(name);

  @override
  Stream<List<StickerPack>> watchCatalog() {
    return _firestore
        .collection('stickerPacks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final packs = <StickerPack>[];
          for (final doc in snapshot.docs) {
            try {
              packs.add(StickerPack.fromJson(doc.id, doc.data()));
            } catch (_) {
              // 形の崩れた1件のために、一覧全体を落とさない。
            }
          }
          return packs;
        });
  }

  @override
  Future<Map<String, CreatorProfile>> loadCreators(
    Iterable<String> creatorIds,
  ) async {
    final ids = creatorIds.where((id) => id.isNotEmpty).toSet().toList();
    final result = <String, CreatorProfile>{};
    // `whereIn`は30件まで。
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      try {
        final snapshot = await _firestore
            .collection('creatorProfiles')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snapshot.docs) {
          result[doc.id] = CreatorProfile.fromJson(doc.id, doc.data());
        }
      } catch (_) {
        // プロフィールが読めなくても、一覧は出す。
      }
    }
    return result;
  }

  Stream<Set<String>> _watchIds(String userId, String name) {
    return _userCollection(
      userId,
      name,
    ).snapshots().map((snapshot) => {for (final doc in snapshot.docs) doc.id});
  }

  @override
  Stream<Set<String>> watchOwnedIds(String userId) =>
      _watchIds(userId, 'ownedStickerPacks');

  @override
  Stream<Set<String>> watchFavouriteIds(String userId) =>
      _watchIds(userId, 'favoritePacks');

  @override
  Stream<Set<String>> watchCartIds(String userId) =>
      _watchIds(userId, 'cartPacks');

  Future<void> _setMembership(
    String userId,
    String name,
    String packId,
    bool on,
  ) async {
    final ref = _userCollection(userId, name).doc(packId);
    if (on) {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  @override
  Future<void> setFavourite(String userId, String packId, {required bool on}) =>
      _setMembership(userId, 'favoritePacks', packId, on);

  @override
  Future<void> setCart(String userId, String packId, {required bool on}) =>
      _setMembership(userId, 'cartPacks', packId, on);

  @override
  Future<void> acquireFree(String packId) async {
    try {
      await _functions.httpsCallable('createCheckoutSession').call({
        'packId': packId,
      });
    } on Object catch (error) {
      // 既に持っている時は、成功として扱う（横丁のWeb側と同じ）。
      if (error.toString().contains('already-exists')) return;
      rethrow;
    }
  }
}
