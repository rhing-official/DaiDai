import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/sticker.dart';

/// ペタピタパッケージのカタログ・所有状況を扱うRepository
/// （技術仕様書7.4・7.5参照、2026-08-11追加）。フェーズ①では`stickerPacks`
/// コレクション・`users/{uid}/ownedStickerPacks`サブコレクションとも
/// Firestoreコンソールから手動投入する（daidai横丁実装後は、購入付与用Cloud
/// FunctionがownedStickerPacksへ書き込む想定。firestore.rulesでクライアント
/// からの書き込みは禁止している）。
abstract class StickerRepository {
  /// 頒布されている全ペタピタパッケージのカタログ。
  Stream<List<StickerPack>> watchPacks();

  /// 指定したユーザーが所有しているペタピタパッケージ一覧。
  Stream<List<StickerPack>> watchOwnedPacks(String userId);

  /// [packId]のペタピタパックをアンインストール（所有解除）する。
  /// 購入付与（grantOwnership）の対称形として、サーバー側（Cloud Functions）が
  /// `ownedStickerPacks`ドキュメントの削除と`ownerCount`の減算を行う
  /// （2026-08-11追加、functions/src/index.tsの`uninstallStickerPack`）。
  Future<void> uninstallPack(String packId);
}

class FirestoreStickerRepository implements StickerRepository {
  FirestoreStickerRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       // Cloud Functions（functions/src/index.ts）はasia-northeast1に
       // デプロイしているため、呼び出し側もリージョンを明示する。
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _stickerPacks =>
      _firestore.collection('stickerPacks');

  List<StickerPack> _packsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map((doc) => StickerPack.fromJson(doc.id, doc.data()))
        .toList();
  }

  @override
  Stream<List<StickerPack>> watchPacks() {
    return _stickerPacks.snapshots().map(_packsFromSnapshot);
  }

  @override
  Stream<List<StickerPack>> watchOwnedPacks(String userId) {
    final ownedIds = _firestore
        .collection('users')
        .doc(userId)
        .collection('ownedStickerPacks')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

    return ownedIds.asyncMap((ids) async {
      if (ids.isEmpty) return <StickerPack>[];
      final catalog = await _stickerPacks.get();
      return _packsFromSnapshot(
        catalog,
      ).where((pack) => ids.contains(pack.packId)).toList();
    });
  }

  @override
  Future<void> uninstallPack(String packId) async {
    await _functions.httpsCallable('uninstallStickerPack').call({
      'packId': packId,
    });
  }
}
