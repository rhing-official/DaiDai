import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../utils/google_sign_in_bootstrap.dart';

abstract class AuthRepository {
  Stream<User?> authStateChanges();
  User? get currentUser;
  Future<User> signInWithGoogle();
  Future<User> signInWithApple();
  Future<void> signOut();

  /// 現在ログイン中ユーザーに登録済みの第2要素一覧（2026-08-09追加）。
  /// TOTPを1件でも登録していれば2段階認証が有効な状態とみなす。
  Future<List<MultiFactorInfo>> getEnrolledFactors();

  /// TOTP登録の開始。QRコード（`TotpSecret.generateQrCodeUrl`）・手入力用の
  /// シークレットキーを含む[TotpSecret]を返す。この時点ではまだ登録は
  /// 完了していない（[confirmTotpEnrollment]で確定する）。
  ///
  /// Firebaseの仕様上、直近の再認証が無いと`requires-recent-login`で
  /// 失敗することがある（呼び出し側でGoogle/Apple再ログインを促す）。
  Future<TotpSecret> startTotpEnrollment();

  /// 認証アプリに表示された6桁コードで[startTotpEnrollment]を確定する。
  /// [displayName]は登録済み要素一覧に表示する名前（例: 端末名や日時）。
  Future<void> confirmTotpEnrollment({
    required TotpSecret secret,
    required String oneTimeCode,
    required String displayName,
  });

  /// TOTPを解除する（2段階認証を無効化する）。
  Future<void> unenrollTotp(MultiFactorInfo info);

  /// [startTotpEnrollment]等が`requires-recent-login`で失敗した場合に呼ぶ。
  /// 現在ログイン中のプロバイダ（Google/Apple）で再認証し、Firebase側の
  /// 「直近ログイン」判定を更新する（2026-08-09追加）。
  Future<void> reauthenticate();

  /// QRコードログイン（2026-08-09追加）。未ログイン端末が`qrLoginSessions`に
  /// pendingなセッションを作成し、sessionIdを返す。QRコードには
  /// `daidai:qrlogin:$sessionId`という文字列を埋め込む（実URLではなく、
  /// DaiDaiアプリ内スキャナーが判定できればよいだけの文字列）。
  Future<String> createQrLoginSession();

  /// [sessionId]のステータス（'pending'/'approved'/'claimed'）を監視する。
  Stream<String> watchQrLoginSessionStatus(String sessionId);

  /// ログイン済み端末側が呼ぶ。セッションを承認し、未ログイン端末が
  /// サインインできるようにする（Cloud Functions経由）。
  Future<void> approveQrLoginSession(String sessionId);

  /// 未ログイン端末側が、承認済み（approved）になったセッションを検知したら
  /// 呼ぶ。Cloud Functionsから受け取ったカスタムトークンでサインインまで行う。
  Future<User> claimQrLoginSession(String sessionId);

  /// 現在ログイン中ユーザーが管理者（Firebase Custom Claims `admin: true`）
  /// かどうか（管理画面向け、2026-08-12追加）。[forceRefresh]をtrueにすると
  /// IDトークンを再取得し、直前に付与されたクレームも反映する（初回管理者
  /// 登録直後の確認に使う）。未ログインならfalse。
  Future<bool> isAdmin({bool forceRefresh = false});
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       // Cloud Functions（functions/src/index.ts）はasia-northeast1に
       // デプロイしているため、呼び出し側もリージョンを明示する。
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

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

    await ensureGoogleSignInInitialized();
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

  User get _requireCurrentUser {
    final user = _auth.currentUser;
    if (user == null) throw StateError('ログインしていません');
    return user;
  }

  @override
  Future<List<MultiFactorInfo>> getEnrolledFactors() {
    return _requireCurrentUser.multiFactor.getEnrolledFactors();
  }

  @override
  Future<TotpSecret> startTotpEnrollment() async {
    final session = await _requireCurrentUser.multiFactor.getSession();
    return TotpMultiFactorGenerator.generateSecret(session);
  }

  @override
  Future<void> confirmTotpEnrollment({
    required TotpSecret secret,
    required String oneTimeCode,
    required String displayName,
  }) async {
    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(
      secret,
      oneTimeCode,
    );
    await _requireCurrentUser.multiFactor.enroll(
      assertion,
      displayName: displayName,
    );
  }

  @override
  Future<void> unenrollTotp(MultiFactorInfo info) {
    return _requireCurrentUser.multiFactor.unenroll(multiFactorInfo: info);
  }

  @override
  Future<void> reauthenticate() async {
    final user = _requireCurrentUser;
    final providerId = user.providerData.isNotEmpty
        ? user.providerData.first.providerId
        : GoogleAuthProvider.PROVIDER_ID;

    if (providerId == 'apple.com') {
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
      if (kIsWeb) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
      return;
    }

    if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }

    await ensureGoogleSignInInitialized();
    final account = await _googleSignIn.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  CollectionReference<Map<String, dynamic>> get _qrLoginSessions =>
      _firestore.collection('qrLoginSessions');

  @override
  Future<String> createQrLoginSession() async {
    final ref = await _qrLoginSessions.add({
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Stream<String> watchQrLoginSessionStatus(String sessionId) {
    return _qrLoginSessions
        .doc(sessionId)
        .snapshots()
        .map((doc) => doc.data()?['status'] as String? ?? 'expired');
  }

  @override
  Future<void> approveQrLoginSession(String sessionId) async {
    await _functions.httpsCallable('approveQrLoginSession').call({
      'sessionId': sessionId,
    });
  }

  @override
  Future<User> claimQrLoginSession(String sessionId) async {
    final result = await _functions.httpsCallable('claimQrLoginSession').call({
      'sessionId': sessionId,
    });
    final customToken = (result.data as Map)['customToken'] as String;
    final userCredential = await _auth.signInWithCustomToken(customToken);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('QRコードログインに失敗しました');
    }
    return user;
  }

  @override
  Future<bool> isAdmin({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final result = await user.getIdTokenResult(forceRefresh);
    return result.claims?['admin'] == true;
  }
}
