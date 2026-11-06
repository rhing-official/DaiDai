import 'package:cloud_firestore/cloud_firestore.dart';

/// 相手の呼び名を、自分の画面だけで上書きする機能（2026-11-06）のリポジトリ。
/// 相手が蔵で設定した呼び名の上から重ねて表示する。本人のみが読み書きできる個人設定で、
/// 相手や他の住人には一切見えない（[BlockRepository]と同じ方針）。
abstract class ContactAliasRepository {
  /// 自分が指定した呼び名の一覧（相手のuserId→呼び名）を購読する。
  Stream<Map<String, String>> watchAliases(String userId);

  /// [targetUserId]への呼び名を指定する（既にあれば上書き）。
  Future<void> setAlias({
    required String userId,
    required String targetUserId,
    required String alias,
  });

  /// 指定した呼び名を取り消す（相手の呼び名に戻る）。
  Future<void> clearAlias({
    required String userId,
    required String targetUserId,
  });
}

class FirestoreContactAliasRepository implements ContactAliasRepository {
  FirestoreContactAliasRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _aliasesOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('contactAliases');

  @override
  Stream<Map<String, String>> watchAliases(String userId) {
    return _aliasesOf(userId).snapshots().map((snapshot) {
      final result = <String, String>{};
      for (final doc in snapshot.docs) {
        final alias = doc.data()['alias'];
        if (alias is String && alias.trim().isNotEmpty) {
          result[doc.id] = alias;
        }
      }
      return result;
    });
  }

  @override
  Future<void> setAlias({
    required String userId,
    required String targetUserId,
    required String alias,
  }) async {
    await _aliasesOf(userId).doc(targetUserId).set({
      'alias': alias,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> clearAlias({
    required String userId,
    required String targetUserId,
  }) async {
    await _aliasesOf(userId).doc(targetUserId).delete();
  }
}
