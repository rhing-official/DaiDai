import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

abstract class UserRepository {
  Future<AppUser?> getUser(String userId);
  Future<void> createUser(AppUser user);
  Future<AppUser?> findByRhingId(String rhingId);
  Future<bool> isRhingIdAvailable(String rhingId);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<AppUser?> getUser(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    return AppUser.fromJson(doc.data()!);
  }

  @override
  Future<void> createUser(AppUser user) async {
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
}
