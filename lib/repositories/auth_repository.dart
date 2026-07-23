import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract class AuthRepository {
  Stream<User?> authStateChanges();
  User? get currentUser;
  Future<User> signInWithGoogle();
  Future<User> signInWithApple();
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
  Future<User> signInWithApple() async {
    // Appleは"email"/"name"スコープをリクエストしないとユーザーの氏名・メールアドレスを
    // 取得できない（Googleと違い初回サインイン時のみクライアントに返る）。
    // ただしDaiDaiはメールアドレスを収集しない方針のため、認証用途のみに使い保存しない。
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');

    // WebはFirebase Auth JS SDKのポップアップフローに任せる（Googleと同じ理由）。
    // Web以外（Android/Windows/Linux）はsignInWithProviderの汎用OAuthフローを使う。
    // iOS/macOSはApple審査ガイドライン(4.8)によりネイティブのSign in with Apple
    // （sign_in_with_appleパッケージ）への切り替えが将来必要になる可能性がある
    // （フェーズ1の優先実装順ではWeb/Android/Windows/Linuxが先のため現状は未対応）。
    final userCredential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('Apple認証に失敗しました');
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
