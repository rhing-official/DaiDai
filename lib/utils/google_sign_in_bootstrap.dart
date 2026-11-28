import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// FirebaseのウェブクライアントID（`android/app/google-services.json`の`client_type: 3`と同じ値。
/// 公開前提のOAuthクライアントID）。Firebase Console > Authentication > Sign-in method >
/// Google > ウェブSDK構成の値。
///
/// Androidのgoogle_sign_inは、`serverClientId`が無いと、リソース`default_web_client_id`を
/// 名前で探す。このリソースはコードから参照されないため、リリースビルドのリソース縮小で
/// 消されることがあり、その時`serverClientId must be provided on Android, null`で
/// ログインに失敗していた（2026-11-28）。そのため、リソースに頼らず、コードから明示的に渡す。
/// 値が`google-services.json`と一致することは`test/google_sign_in_config_test.dart`が守る。
const String googleWebClientId =
    '380243513330-n5mejgg1sberbkjhrtgf5qti6js9gf26.apps.googleusercontent.com';

/// `GoogleSignIn.instance.initialize()`は「アプリ全体で厳密に1回だけ」
/// 呼ばなければならない制約がある（2回目以降の呼び出しは未定義動作、
/// パッケージ本体のドキュメントコメント参照）。`AuthRepository`（ログイン時、
/// Web以外）と`GoogleCalendarAuthService`（Googleカレンダー連携時、2026-09-01
/// 追加）の両方が初期化を必要とする為、呼び出し元によらず1回だけ実行される
/// ようFutureをキャッシュして共有する。
///
/// [clientId]は最初に呼ばれた側の値が採用される（2回目以降の呼び出しでは
/// 無視される）。Web以外は`null`（プラットフォームの設定ファイルから読む）で
/// 事足りるが、Webは`GoogleCalendarAuthService`がGoogleカレンダーのスコープ
/// 同意を取る為に明示的なWeb用クライアントIDを渡す必要がある
/// （`GoogleCalendarAuthService`のコメント参照）。
Future<void> ensureGoogleSignInInitialized({String? clientId}) {
  return _initializeFuture ??= GoogleSignIn.instance.initialize(
    clientId: clientId,
    serverClientId: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? googleWebClientId
        : null,
  );
}

Future<void>? _initializeFuture;
