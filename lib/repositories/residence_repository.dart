import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/residence.dart';

/// 住人の居住地（自己申告）を扱うリポジトリ。`users/{uid}`本体は全ログイン者が
/// 読めるため、本人のみ読み書きできる`users/{uid}/private/residence`に置く。
abstract class ResidenceRepository {
  /// 未回答なら`null`。
  Future<Residence?> getResidence(String userId);

  Future<void> saveResidence(String userId, Residence residence);
}

class FirestoreResidenceRepository implements ResidenceRepository {
  FirestoreResidenceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _docOf(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('private')
      .doc('residence');

  @override
  Future<Residence?> getResidence(String userId) async {
    final snapshot = await _docOf(userId).get();
    final data = snapshot.data();
    if (data == null || data['countryCode'] is! String) return null;
    return Residence.fromJson(data);
  }

  @override
  Future<void> saveResidence(String userId, Residence residence) async {
    // 都道府県・タイムゾーンを外す変更でも古い値が残らないよう、
    // マージせず丸ごと置き換える。
    await _docOf(
      userId,
    ).set({...residence.toJson(), 'updatedAt': FieldValue.serverTimestamp()});
  }
}
