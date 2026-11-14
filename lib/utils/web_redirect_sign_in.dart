import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web版でGoogleログインを同じタブのリダイレクトで行う本番ドメイン（2026-11-14）。
/// Firebaseの認証画面（`/__/auth/*`）をこのドメイン経由にする（`cloudflare/worker.js`が
/// `daidai-rhing.firebaseapp.com`へ中継）ことで、最近のブラウザ（Chrome・Safari・Firefox）の
/// ストレージ分離があっても、Googleから戻った後にログイン状態を取れる。
/// 他のドメイン（localhost・`*.pages.dev`）は、中継が無いので従来のポップアップのまま。
const kWebAuthProxyHost = 'daidai.rhing.jp';

/// Googleログインを（ポップアップではなく）同じタブのリダイレクトで行うか。
bool get useWebRedirectSignIn => kIsWeb && Uri.base.host == kWebAuthProxyHost;

Future<void>? _redirectResult;

/// リダイレクトでログインして戻ってきた時の結果を、一度だけ取得する。ログインが成功していれば
/// 認証状態に反映済みで、2段階認証が必要なら[FirebaseAuthMultiFactorException]、失敗なら
/// [FirebaseAuthException]を投げる。同じFutureを複数の呼び出し側で待てる（起動時と
/// ログイン画面）。リダイレクトを使わない環境では何もしない。
Future<void> awaitWebRedirectResult() {
  return _redirectResult ??= useWebRedirectSignIn
      ? FirebaseAuth.instance.getRedirectResult().then((_) {})
      : Future<void>.value();
}
