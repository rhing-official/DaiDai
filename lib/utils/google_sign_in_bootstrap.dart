import 'package:google_sign_in/google_sign_in.dart';

/// `GoogleSignIn.instance.initialize()`は「アプリ全体で厳密に1回だけ」
/// 呼ばなければならない制約がある（2回目以降の呼び出しは未定義動作、
/// パッケージ本体のドキュメントコメント参照）。`AuthRepository`（ログイン時、
/// Web以外）と`GoogleCalendarAuthService`（Googleカレンダー連携時、2026-09-01
/// 追加）の両方が初期化を必要とするため、呼び出し元によらず1回だけ実行される
/// ようFutureをキャッシュして共有する。
///
/// [clientId]は最初に呼ばれた側の値が採用される（2回目以降の呼び出しでは
/// 無視される）。Web以外は`null`（プラットフォームの設定ファイルから読む）で
/// 事足りるが、Webは`GoogleCalendarAuthService`がGoogleカレンダーのスコープ
/// 同意を取るために明示的なWeb用クライアントIDを渡す必要がある
/// （`GoogleCalendarAuthService`のコメント参照）。
Future<void> ensureGoogleSignInInitialized({String? clientId}) {
  return _initializeFuture ??= GoogleSignIn.instance.initialize(
    clientId: clientId,
  );
}

Future<void>? _initializeFuture;
