import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract class AuthRepository {
  Stream<User?> authStateChanges();
  User? get currentUser;
  Future<User> signInWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<User> signInWithGoogle() async {
    // google_sign_inのauthenticate()はWebでは未対応（GIS SDKのボタンUI経由のみ許可）。
    // WebはFirebase Auth JS SDK側のポップアップフローに任せる。
    if (kIsWeb) {
      final userCredential = await _auth.signInWithPopup(GoogleAuthProvider());
      final user = userCredential.user;
      if (user == null) {
        throw StateError('Google認証に失敗しました');
      }
      return user;
    }

    await _googleSignIn.initialize();
    final account = await _googleSignIn.authenticate();
    final googleAuth = account.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Google認証に失敗しました');
    }
    return user;
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    await _auth.signOut();
  }
}
