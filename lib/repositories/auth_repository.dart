import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/availability.dart';
import 'package:passkeys/types.dart';
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';

import '../utils/google_sign_in_bootstrap.dart';

/// 秘密の質問1組（設定時の入力用、2026-09-16追加）。
class SecretQuestionInput {
  const SecretQuestionInput({required this.question, required this.answer});
  final String question;
  final String answer;
}

/// 秘密の質問の設定状況（ハッシュ自体は含まない、2026-09-16追加）。
class SecretQuestionsStatus {
  const SecretQuestionsStatus({required this.configured, this.updatedAt});
  final bool configured;
  final DateTime? updatedAt;
}

/// 登録済みパスキー1件のメタ情報（設定画面の一覧表示用、2026-09-16追加）。
class PasskeyCredentialInfo {
  const PasskeyCredentialInfo({
    required this.id,
    required this.deviceType,
    required this.backedUp,
    this.createdAt,
    this.lastUsedAt,
    this.name,
  });
  final String id;
  final String deviceType;
  final bool backedUp;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// 住人が付けた任意の名前（2026-09-18追加）。未設定なら`null`で、一覧では
  /// 作成日時にフォールバック表示する。
  final String? name;
}

/// パスキー紛失時の復旧フロー第1段階で返される質問一覧（2026-09-16追加）。
class PasskeyRecoveryQuestions {
  const PasskeyRecoveryQuestions({
    required this.recoveryId,
    required this.questions,
  });
  final String recoveryId;
  final List<String> questions;
}

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

  /// Rhing ID＋パスキー（WebAuthn）による新規アカウント作成（2026-09-16追加）。
  /// デバイスの生体認証/画面ロックで新しいパスキーを作成し、対応する
  /// Firebase Authユーザーを作成してサインインする。この時点ではまだ
  /// FirestoreのAppUserドキュメントは存在しないため、呼び出し後はGoogle/Apple
  /// サインイン後と同様に`AuthGate`が`TermsConsentScreen`→
  /// `RhingIdSetupScreen`へ自然に遷移する（Rhing ID自体はそこで決める）。
  Future<User> registerWithPasskey();

  /// Rhing ID＋パスキーでのログイン（2026-09-16追加）。[rhingId]に登録済みの
  /// パスキーでデバイスに認証を要求し、成功したらサインインする。
  Future<User> signInWithPasskey(String rhingId);

  /// Conditional UI（パスワードマネージャー自動候補表示）によるパスキー
  /// ログイン（2026-09-16追加、Web版のみ対応）。Rhing IDの入力なしに
  /// ブラウザ側のパスキー候補一覧をユーザーに提示し、選択されたパスキーで
  /// サインインする。ユーザーが候補を選ぶ前に他の操作（Google/Rhing ID
  /// ログイン等）で認証が横取りされた場合はnullを返す。対応していない
  /// 環境（Web以外、またはブラウザがConditional Mediation未対応）では
  /// 呼び出し側が判断できるよう[isConditionalPasskeyAvailable]を用意する。
  Future<User?> trySignInWithConditionalPasskey();

  /// [trySignInWithConditionalPasskey]が実際に使える環境かどうか。
  Future<bool> isConditionalPasskeyAvailable();

  /// [trySignInWithConditionalPasskey]の待機を中断する。呼び出し元の画面が
  /// ユーザーの選択を待たずに閉じられた場合に呼ぶ（明示的なRhing ID
  /// ログイン等、他の認証操作を開始する場合は各操作側が自動的に中断するため
  /// 呼ぶ必要はない）。
  Future<void> cancelConditionalPasskeyAttempt();

  /// 秘密の質問（3問固定）を設定・更新する（2026-09-16追加、パスキー紛失時の
  /// 復旧用）。既存の設定があれば3問まるごと置き換える。回答はサーバー側で
  /// ハッシュ化して保存し、平文は保持しない。
  Future<void> setSecretQuestions(List<SecretQuestionInput> questions);

  /// 秘密の質問の設定状況を取得する（ハッシュ自体は取得できない）。
  Future<SecretQuestionsStatus> getSecretQuestionsStatus();

  /// 現在ログイン中ユーザーが登録済みのパスキー一覧を取得する
  /// （設定画面のパスキー管理UI用）。
  Future<List<PasskeyCredentialInfo>> listPasskeyCredentials();

  /// ログイン中のアカウントに追加のパスキーを登録する（複数端末対応）。
  /// [registerWithPasskey]と異なり新規アカウントは作らず、既存アカウントに
  /// クレデンシャルを追加するだけ。[name]は住人が付けた任意の名前
  /// （2026-09-18追加、設定画面の「追加」フローでのみ入力させる。新規
  /// アカウント作成時のパスキー作成は一発実行のまま名前を挟まない）。
  Future<void> addPasskeyCredential({String? name});

  /// 登録済みパスキーを削除する。
  Future<void> deletePasskeyCredential(String credentialId);

  /// 登録済みパスキーの名前を変更する（2026-09-18追加）。
  Future<void> renamePasskeyCredential(String credentialId, String name);

  /// パスキー紛失時の復旧フロー第1段階（2026-09-16追加）。[rhingId]の
  /// アカウントに秘密の質問が設定されていれば質問一覧を返す。
  Future<PasskeyRecoveryQuestions> beginPasskeyRecovery(String rhingId);

  /// 復旧フロー第2段階。[answers]は[beginPasskeyRecovery]が返した質問と
  /// 同じ順序の3つの回答。3問すべて正解した場合のみサインインする。
  Future<User> finishPasskeyRecovery(String recoveryId, List<String> answers);

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

  /// Cloud Functionsの`HttpsCallableResult.data`は（特にWeb版で）ネストした
  /// マップが`Map<Object?, Object?>`として返ってくることがあり、そのままでは
  /// `Map<String, dynamic>`にキャストできない。JSONを経由して往復させることで
  /// 純粋な`Map<String, dynamic>`/`List<dynamic>`構造に正規化する
  /// （2026-09-16追加、パスキーのregistration/authentication optionsのように
  /// ネストしたレスポンスを扱うため新設）。
  Map<String, dynamic> _asJsonMap(Object? data) =>
      jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<User> registerWithPasskey() async {
    final beginResult = await _functions
        .httpsCallable('beginPasskeyRegistration')
        .call();
    final beginData = _asJsonMap(beginResult.data);
    final challengeId = beginData['challengeId'] as String;
    final options = beginData['options'] as Map<String, dynamic>;

    final authenticator = PasskeyAuthenticator();
    final attestationResponse = await authenticator.register(
      RegisterRequestType.fromJson(options),
    );

    final finishResult = await _functions
        .httpsCallable('finishPasskeyRegistration')
        .call({
          'challengeId': challengeId,
          'attestationResponse': attestationResponse.toJson(),
        });
    final customToken = (finishResult.data as Map)['customToken'] as String;
    final userCredential = await _auth.signInWithCustomToken(customToken);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('パスキーでのアカウント作成に失敗しました');
    }
    return user;
  }

  @override
  Future<User> signInWithPasskey(String rhingId) async {
    final beginResult = await _functions
        .httpsCallable('beginPasskeyAuthentication')
        .call({'rhingId': rhingId});
    final beginData = _asJsonMap(beginResult.data);
    final challengeId = beginData['challengeId'] as String;
    final options = beginData['options'] as Map<String, dynamic>;

    final authenticator = PasskeyAuthenticator();
    final assertionResponse = await authenticator.authenticate(
      AuthenticateRequestType.fromJson(options),
    );

    final finishResult = await _functions
        .httpsCallable('finishPasskeyAuthentication')
        .call({
          'challengeId': challengeId,
          'assertionResponse': assertionResponse.toJson(),
        });
    final customToken = (finishResult.data as Map)['customToken'] as String;
    final userCredential = await _auth.signInWithCustomToken(customToken);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('パスキーログインに失敗しました');
    }
    return user;
  }

  @override
  Future<bool> isConditionalPasskeyAvailable() async {
    if (!kIsWeb) return false;
    final availability = await GetAvailability(
      platform: PasskeysPlatform.instance,
    ).web();
    return availability.isConditionalMediationAvailable ?? false;
  }

  @override
  Future<User?> trySignInWithConditionalPasskey() async {
    if (!kIsWeb) return null;
    final beginResult = await _functions
        .httpsCallable('beginPasskeyAuthenticationDiscoverable')
        .call();
    final beginData = _asJsonMap(beginResult.data);
    final challengeId = beginData['challengeId'] as String;
    final options = beginData['options'] as Map<String, dynamic>;

    final authenticator = PasskeyAuthenticator();
    final AuthenticateResponseType assertionResponse;
    try {
      assertionResponse = await authenticator.authenticate(
        AuthenticateRequestType.fromJson(
          options,
          mediation: MediationType.Conditional,
        ),
      );
    } on PasskeyAuthCancelledException {
      return null;
    } on NoCredentialsAvailableException {
      return null;
    }

    final finishResult = await _functions
        .httpsCallable('finishPasskeyAuthenticationDiscoverable')
        .call({
          'challengeId': challengeId,
          'assertionResponse': assertionResponse.toJson(),
        });
    final customToken = (finishResult.data as Map)['customToken'] as String;
    final userCredential = await _auth.signInWithCustomToken(customToken);
    return userCredential.user;
  }

  @override
  Future<void> cancelConditionalPasskeyAttempt() {
    return PasskeyAuthenticator().cancelCurrentAuthenticatorOperation();
  }

  @override
  Future<void> setSecretQuestions(List<SecretQuestionInput> questions) async {
    await _functions.httpsCallable('setSecretQuestions').call({
      'questions': questions
          .map((q) => {'question': q.question, 'answer': q.answer})
          .toList(),
    });
  }

  @override
  Future<SecretQuestionsStatus> getSecretQuestionsStatus() async {
    final result = await _functions
        .httpsCallable('getSecretQuestionsStatus')
        .call();
    final data = _asJsonMap(result.data);
    final updatedAtMs = data['updatedAt'] as int?;
    return SecretQuestionsStatus(
      configured: data['configured'] as bool,
      updatedAt: updatedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  @override
  Future<List<PasskeyCredentialInfo>> listPasskeyCredentials() async {
    final result = await _functions
        .httpsCallable('listPasskeyCredentials')
        .call();
    final data = _asJsonMap(result.data);
    final credentials = data['credentials'] as List<dynamic>;
    return credentials.map((raw) {
      final c = raw as Map<String, dynamic>;
      final createdAtMs = c['createdAt'] as int?;
      final lastUsedAtMs = c['lastUsedAt'] as int?;
      return PasskeyCredentialInfo(
        id: c['id'] as String,
        deviceType: c['deviceType'] as String,
        backedUp: c['backedUp'] as bool,
        createdAt: createdAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
        lastUsedAt: lastUsedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastUsedAtMs),
        name: c['name'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> addPasskeyCredential({String? name}) async {
    final beginResult = await _functions
        .httpsCallable('beginAddPasskey')
        .call();
    final beginData = _asJsonMap(beginResult.data);
    final challengeId = beginData['challengeId'] as String;
    final options = beginData['options'] as Map<String, dynamic>;

    final authenticator = PasskeyAuthenticator();
    final attestationResponse = await authenticator.register(
      RegisterRequestType.fromJson(options),
    );

    await _functions.httpsCallable('finishAddPasskey').call({
      'challengeId': challengeId,
      'attestationResponse': attestationResponse.toJson(),
      'name': name,
    });
  }

  @override
  Future<void> deletePasskeyCredential(String credentialId) async {
    await _functions.httpsCallable('deletePasskeyCredential').call({
      'credentialId': credentialId,
    });
  }

  @override
  Future<void> renamePasskeyCredential(String credentialId, String name) async {
    await _functions.httpsCallable('renamePasskeyCredential').call({
      'credentialId': credentialId,
      'name': name,
    });
  }

  @override
  Future<PasskeyRecoveryQuestions> beginPasskeyRecovery(String rhingId) async {
    final result = await _functions.httpsCallable('beginPasskeyRecovery').call({
      'rhingId': rhingId,
    });
    final data = _asJsonMap(result.data);
    final questions = (data['questions'] as List<dynamic>).cast<String>();
    return PasskeyRecoveryQuestions(
      recoveryId: data['recoveryId'] as String,
      questions: questions,
    );
  }

  @override
  Future<User> finishPasskeyRecovery(
    String recoveryId,
    List<String> answers,
  ) async {
    final result = await _functions.httpsCallable('finishPasskeyRecovery').call(
      {'recoveryId': recoveryId, 'answers': answers},
    );
    final customToken = (result.data as Map)['customToken'] as String;
    final userCredential = await _auth.signInWithCustomToken(customToken);
    final user = userCredential.user;
    if (user == null) {
      throw StateError('アカウントの復旧に失敗しました');
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
