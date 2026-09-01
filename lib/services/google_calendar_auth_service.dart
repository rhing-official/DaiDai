import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../utils/google_sign_in_bootstrap.dart';

/// Web版でPhase 0（[GoogleCalendarAuthService._webClientId]へのOAuth
/// クライアントID設定）が未完了のまま連携を試みたときに投げる（2026-09-01
/// 追加）。呼び出し側はこれを型で捕捉し、`google_sign_in_web`パッケージが
/// 出す生の`Assertion failed: ... appClientId != null ...`をそのまま
/// ユーザーに見せず、分かりやすい文言に置き換える。
class GoogleCalendarNotConfiguredException implements Exception {
  const GoogleCalendarNotConfiguredException();
}

/// Googleカレンダー連携（2026-09-01追加）のスコープ同意・アクセストークン
/// 取得を担う。サーバー（Cloud Functions）にはリフレッシュトークンを一切
/// 保存しないクライアント主導の同期方式のため、ここで取得したアクセス
/// トークンはその場限りで使い切り、永続化しない（呼び出し側の
/// `GoogleCalendarSyncService`参照）。
///
/// `google_sign_in`パッケージの`authorizationClient`（v7.2.0で追加された
/// スコープ管理API）をラップする。`GoogleSignIn.instance.initialize()`は
/// アプリ全体で1回しか呼べない制約があるため、`AuthRepository`と共有の
/// [ensureGoogleSignInInitialized]を経由する。
class GoogleCalendarAuthService {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/calendar.events',
  ];

  /// Web専用のOAuthクライアントID。
  ///
  /// Web版の`AuthRepository.signInWithGoogle`はgoogle_sign_inパッケージを
  /// 使わずFirebase Auth JS SDKの`signInWithPopup`で直接ログインしている
  /// ため、`GoogleSignIn.instance.initialize()`がWebでは誰にも呼ばれていない。
  /// Googleカレンダーのスコープ同意（`authorizationClient`）はWebでも
  /// google_sign_inパッケージ経由で行うため、このサービスが初めてWebで
  /// `initialize()`を呼ぶことになり、その際は設定ファイルに頼れず明示的な
  /// クライアントIDが必須になる。
  ///
  /// Firebase Console（Authentication > Sign-in method > Google >
  /// ウェブSDK構成 > ウェブ クライアント ID）から取得した値
  /// （2026-09-01設定、Phase 0完了）。
  static const String? _webClientId =
      '380243513330-n5mejgg1sberbkjhrtgf5qti6js9gf26.apps.googleusercontent.com';

  Future<void> ensureInitialized() {
    return ensureGoogleSignInInitialized(
      clientId: kIsWeb ? _webClientId : null,
    );
  }

  /// 設定画面・初回確認ダイアログの「同期する」から呼ぶ。ユーザー操作の
  /// 直後であることが前提（同意ポップアップが出ることがある）。
  ///
  /// ユーザーが同意画面でキャンセルした場合はfalseを返す（呼び出し側は
  /// `googleCalendarSyncEnabled`を更新せずnullのまま据え置く）。それ以外の
  /// 失敗（ネットワークエラー・設定不備等）は例外をそのまま投げる。
  Future<bool> requestConsent() async {
    if (kIsWeb && _webClientId == null) {
      throw const GoogleCalendarNotConfiguredException();
    }
    await ensureInitialized();
    try {
      await GoogleSignIn.instance.authorizationClient.authorizeScopes(_scopes);
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
  }

  /// `CalendarSyncWorker`専用。無言でアクセストークンを取得する。
  /// 未同意・失効している場合はnullを返す（呼び出し側は同期をスキップする）。
  Future<String?> getAccessTokenSilently() async {
    await ensureInitialized();
    final authorization = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(_scopes);
    return authorization?.accessToken;
  }
}
