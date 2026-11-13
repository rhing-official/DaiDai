import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Windows・LinuxでのGoogleログイン（2026-11-13）。`google_sign_in`はこの2つに未対応
/// （`UnimplementedError`）のため、既定のブラウザでGoogleの認証画面を開き、
/// `http://127.0.0.1:{ポート}`（ループバック）で認可コードを受け取る方式にする
/// （Googleの「デスクトップ アプリ」向けのOAuth、PKCE付き）。受け取った認可コードを
/// IDトークンに交換し、呼び出し側がFirebase Authの資格情報にする。
///
/// OAuthクライアントは、Google Cloudの「デスクトップ アプリ」種別のもの。クライアントIDと
/// シークレット（デスクトップ向けは公開前提）は、ビルド時の`--dart-define`で渡し、
/// リポジトリには入れない。
class GoogleDesktopSignIn {
  GoogleDesktopSignIn({
    this.clientId = const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID'),
    this.clientSecret = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    ),
    http.Client? httpClient,
    Future<bool> Function(Uri url)? openBrowser,
    Duration timeout = const Duration(minutes: 5),
  }) : _http = httpClient ?? http.Client(),
       _openBrowser = openBrowser ?? ((url) => launchUrl(url)),
       _timeout = timeout;

  final String clientId;
  final String clientSecret;
  final http.Client _http;
  final Future<bool> Function(Uri url) _openBrowser;
  final Duration _timeout;

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// ブラウザでログインさせ、GoogleのIDトークンを返す。キャンセル・失敗は例外。
  Future<String> signInIdToken() async {
    if (!isConfigured) {
      throw const GoogleDesktopSignInException(
        'Googleログインの設定（GOOGLE_DESKTOP_CLIENT_ID・GOOGLE_DESKTOP_CLIENT_SECRET）がありません',
      );
    }
    final verifier = generateCodeVerifier();
    final state = generateCodeVerifier(length: 24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final url = buildAuthUrl(
        clientId: clientId,
        redirectUri: redirectUri,
        codeChallenge: codeChallengeFor(verifier),
        state: state,
      );
      if (!await _openBrowser(url)) {
        throw const GoogleDesktopSignInException('ブラウザを開けませんでした');
      }
      final code = await _waitForCode(server, state).timeout(
        _timeout,
        onTimeout: () =>
            throw const GoogleDesktopSignInException('ログインがタイムアウトしました'),
      );
      return await _exchange(code, verifier, redirectUri);
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      // faviconなど、認可と関係のない要求は無視する。
      if (!params.containsKey('code') && !params.containsKey('error')) {
        request.response.statusCode = 404;
        await request.response.close();
        continue;
      }
      final error = params['error'];
      final ok = error == null && params['state'] == state;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><meta charset="utf-8"><title>DaiDai</title>'
          '<body style="font-family:sans-serif;text-align:center;margin-top:20vh">'
          '${ok ? 'ログインできました。このタブを閉じて、DaiDaiに戻ってください。' : 'ログインできませんでした。DaiDaiに戻って、もう一度お試しください。'}'
          '</body>',
        );
      await request.response.close();
      if (error != null) {
        throw GoogleDesktopSignInException('Googleログインが中止されました（$error）');
      }
      if (params['state'] != state) {
        throw const GoogleDesktopSignInException('ログインの状態が一致しません');
      }
      return params['code']!;
    }
    throw const GoogleDesktopSignInException('ログインが完了しませんでした');
  }

  Future<String> _exchange(
    String code,
    String verifier,
    String redirectUri,
  ) async {
    final response = await _http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
    );
    final json = jsonDecode(response.body);
    final idToken = json is Map ? json['id_token'] : null;
    if (response.statusCode != 200 || idToken is! String) {
      throw GoogleDesktopSignInException(
        'Googleのトークンを取得できませんでした（${response.statusCode}）',
      );
    }
    return idToken;
  }

  /// PKCEの`code_verifier`（43〜128文字の乱数）。
  static String generateCodeVerifier({int length = 64, Random? random}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = random ?? Random.secure();
    return List.generate(
      length,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
  }

  /// `code_challenge`（verifierのSHA-256をbase64url・パディング無しにしたもの）。
  static String codeChallengeFor(String verifier) => base64UrlEncode(
    sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');

  static Uri buildAuthUrl({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
  }) => Uri.parse(_authEndpoint).replace(
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
    },
  );
}

class GoogleDesktopSignInException implements Exception {
  const GoogleDesktopSignInException(this.message);
  final String message;

  @override
  String toString() => message;
}
