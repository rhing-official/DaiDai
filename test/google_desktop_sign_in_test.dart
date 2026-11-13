import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:daidai/services/google_desktop_sign_in.dart';

void main() {
  test('code_challengeは、RFC 7636の例のverifierから正しく作られる', () {
    expect(
      GoogleDesktopSignIn.codeChallengeFor(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      ),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('verifierは43文字以上で、使える文字だけ', () {
    final v = GoogleDesktopSignIn.generateCodeVerifier();
    expect(v.length, greaterThanOrEqualTo(43));
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
  });

  test('認証URLにPKCEとループバックの戻り先が入る', () {
    final url = GoogleDesktopSignIn.buildAuthUrl(
      clientId: 'cid',
      redirectUri: 'http://127.0.0.1:1234',
      codeChallenge: 'ch',
      state: 'st',
    );
    expect(url.host, 'accounts.google.com');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['redirect_uri'], 'http://127.0.0.1:1234');
    expect(url.queryParameters['scope'], 'openid email profile');
  });

  test('設定が無ければ、ブラウザを開く前に失敗する', () async {
    final signIn = GoogleDesktopSignIn(clientId: '', clientSecret: '');
    expect(signIn.isConfigured, isFalse);
    expect(
      signIn.signInIdToken(),
      throwsA(isA<GoogleDesktopSignInException>()),
    );
  });

  test('ブラウザへ戻ってきた認可コードをIDトークンに交換する', () async {
    late Map<String, String> sent;
    final client = MockClient((request) async {
      sent = request.bodyFields;
      return http.Response(jsonEncode({'id_token': 'ID-TOKEN'}), 200);
    });
    final signIn = GoogleDesktopSignIn(
      clientId: 'cid',
      clientSecret: 'secret',
      httpClient: client,
      openBrowser: (url) async {
        // ブラウザの代わりに、戻り先へ認可コードを返す。
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final state = url.queryParameters['state']!;
        // 本物のブラウザと同じく、開く処理は待たずに、戻りの要求を後で届ける。
        unawaited(
          _visit(
            redirect.replace(queryParameters: {'code': 'abc', 'state': state}),
          ),
        );
        return true;
      },
    );
    expect(await signIn.signInIdToken(), 'ID-TOKEN');
    expect(sent['code'], 'abc');
    expect(sent['grant_type'], 'authorization_code');
    expect(sent['code_verifier'], isNotEmpty);
  });

  test('stateが違う戻りは拒否する', () async {
    final signIn = GoogleDesktopSignIn(
      clientId: 'cid',
      clientSecret: 'secret',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      openBrowser: (url) async {
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        unawaited(
          _visit(
            redirect.replace(queryParameters: {'code': 'abc', 'state': 'bad'}),
          ),
        );
        return true;
      },
    );
    expect(
      signIn.signInIdToken(),
      throwsA(isA<GoogleDesktopSignInException>()),
    );
  });
}

Future<void> _visit(Uri url) async {
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  await response.drain<void>();
}
