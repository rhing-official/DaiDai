import 'dart:async';
import 'dart:convert';

import 'package:daidai/services/app_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// WindowsとLinuxでCloud Functionsを呼ぶ、HTTPSの直接呼び出し（callableのプロトコル）の確認。
AppFunctions _rest(
  http.Client client, {
  String? token = 'token-1',
  Duration timeout = const Duration(seconds: 5),
}) => AppFunctions.rest(
  region: 'asia-northeast1',
  client: client,
  projectId: 'daidai-rhing',
  idToken: () async => token,
  timeout: timeout,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('URL・ヘッダー・本文がcallableの形で送られ、resultが返る', () async {
    late http.Request sent;
    final functions = _rest(
      MockClient((request) async {
        sent = request;
        return _json({
          'result': {'sessionId': 'abc'},
        });
      }),
    );

    final result = await functions
        .httpsCallable('createIssuedQrLoginSession')
        .call({'deviceName': 'PC', 'count': 2});

    expect(
      sent.url.toString(),
      'https://asia-northeast1-daidai-rhing.cloudfunctions.net/createIssuedQrLoginSession',
    );
    expect(sent.method, 'POST');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(sent.headers['Authorization'], 'Bearer token-1');
    expect(jsonDecode(sent.body), {
      'data': {'deviceName': 'PC', 'count': 2},
    });
    expect((result.data as Map)['sessionId'], 'abc');
  });

  test('引数なしの呼び出しは data: null を送る', () async {
    late http.Request sent;
    final functions = _rest(
      MockClient((request) async {
        sent = request;
        return _json({'result': null});
      }),
    );

    final result = await functions
        .httpsCallable('deleteAccountImmediately')
        .call();

    expect(jsonDecode(sent.body), {'data': null});
    expect(result.data, isNull);
  });

  test('ログインしていない（IDトークンが無い）時はAuthorizationを付けない', () async {
    late http.Request sent;
    final functions = _rest(
      MockClient((request) async {
        sent = request;
        return _json({'result': 'ok'});
      }),
      token: null,
    );

    await functions.httpsCallable('beginPasskeyAuthentication').call({});

    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('関数のエラーはstatusをFirebaseのコードに直して、message・detailsと共に投げる', () async {
    final functions = _rest(
      MockClient(
        (request) async => _json({
          'error': {
            'message': '100日に1回までです',
            'status': 'FAILED_PRECONDITION',
            'details': {'nextAvailable': '2027-02-01'},
          },
        }, 400),
      ),
    );

    await expectLater(
      functions.httpsCallable('changeRhingSeed').call({'seed': 'x'}),
      throwsA(
        isA<AppFunctionsException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', '100日に1回までです')
            .having((e) => e.details, 'details', {
              'nextAvailable': '2027-02-01',
            }),
      ),
    );
  });

  test('statusの無い失敗は、HTTPのステータスコードからコードを決める', () async {
    for (final (status, code) in [
      (401, 'unauthenticated'),
      (403, 'permission-denied'),
      (404, 'not-found'),
      (429, 'resource-exhausted'),
      (503, 'unavailable'),
      (500, 'internal'),
    ]) {
      final functions = _rest(
        MockClient((request) async => http.Response('', status)),
      );
      await expectLater(
        functions.httpsCallable('x').call(),
        throwsA(
          isA<AppFunctionsException>().having((e) => e.code, 'code', code),
        ),
        reason: 'HTTP $status',
      );
    }
  });

  test('通信できない時はunavailable', () async {
    final functions = _rest(
      MockClient((request) async => throw http.ClientException('接続できません')),
    );

    await expectLater(
      functions.httpsCallable('x').call(),
      throwsA(
        isA<AppFunctionsException>()
            .having((e) => e.code, 'code', 'unavailable')
            .having((e) => e.message, 'message', '接続できません'),
      ),
    );
  });

  test('時間内に返らなければdeadline-exceeded', () async {
    final functions = _rest(
      MockClient((request) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      functions.httpsCallable('x').call(),
      throwsA(
        isA<AppFunctionsException>().having(
          (e) => e.code,
          'code',
          'deadline-exceeded',
        ),
      ),
    );
  });

  test('成功の応答にresultが無ければinternal', () async {
    final functions = _rest(MockClient((request) async => _json({'foo': 1})));

    await expectLater(
      functions.httpsCallable('x').call(),
      throwsA(
        isA<AppFunctionsException>().having((e) => e.code, 'code', 'internal'),
      ),
    );
  });

  test('日本語の応答を文字化けせずに読める', () async {
    final functions = _rest(
      MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(jsonEncode({'result': 'こんにちは'})),
          200,
        ),
      ),
    );

    final result = await functions.httpsCallable('x').call();

    expect(result.data, 'こんにちは');
  });
}
