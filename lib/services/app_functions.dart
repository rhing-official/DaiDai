import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cloud Functions（callable）の呼び出し口（2026-11-12追加）。
///
/// `cloud_functions`パッケージはWindows・Linuxに実装が無く、`FirebaseFunctions`を
/// 直接使うとそれらのプラットフォームでは呼び出しが一切できない。そのため
/// アプリ内ではこのクラスを経由して呼び出す:
/// - Android・iOS・macOS・Web: 従来どおり`cloud_functions`のSDKに任せる。
/// - Windows・Linux: callableのHTTPSプロトコル（`POST https://{リージョン}-{プロジェクトID}.cloudfunctions.net/{関数名}`、
///   本体は`{"data": ...}`、認証は`Authorization: Bearer <IDトークン>`）で直接呼ぶ。
///
/// 使い方は`FirebaseFunctions`と同じ（`instanceFor(region:)` → `httpsCallable(name)` →
/// `call(data)`）。失敗は[AppFunctionsException]（`code`・`message`・`details`）で投げる。
class AppFunctions {
  AppFunctions._(this._region, this._rest);

  /// [region]のCloud Functionsを呼ぶ口を返す（`FirebaseFunctions.instanceFor`と同じ形）。
  factory AppFunctions.instanceFor({required String region}) =>
      AppFunctions._(region, null);

  /// HTTPSで直接呼ぶ実装を、依存を差し替えて作る（テスト用）。
  @visibleForTesting
  factory AppFunctions.rest({
    required String region,
    required http.Client client,
    required String projectId,
    required Future<String?> Function() idToken,
    Duration timeout = const Duration(seconds: 70),
  }) => AppFunctions._(
    region,
    _RestConfig(
      client: client,
      projectId: () => projectId,
      idToken: idToken,
      timeout: timeout,
    ),
  );

  final String _region;
  final _RestConfig? _rest;

  /// このプラットフォームで`cloud_functions`のSDKが使えず、HTTPSで直接呼ぶ必要があるか。
  static bool get usesRest =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  AppCallable httpsCallable(String name) {
    final rest =
        _rest ??
        (usesRest
            ? _RestConfig(
                client: http.Client(),
                projectId: () => Firebase.app().options.projectId,
                idToken: () async =>
                    FirebaseAuth.instance.currentUser?.getIdToken(),
                timeout: const Duration(seconds: 70),
              )
            : null);
    if (rest != null) {
      return _RestCallable(region: _region, name: name, config: rest);
    }
    return _SdkCallable(name: name, region: _region);
  }
}

/// callableの呼び出し1件（`HttpsCallable`相当）。
abstract interface class AppCallable {
  Future<AppCallableResult> call([Object? parameters]);
}

/// callableの戻り値（`HttpsCallableResult`相当）。
class AppCallableResult {
  const AppCallableResult(this.data);

  /// 関数が返した値（JSONとして読める`Map`・`List`・文字列・数値・真偽値・null）。
  final dynamic data;
}

/// Cloud Functionsの呼び出しの失敗（`FirebaseFunctionsException`相当）。
///
/// `code`は`invalid-argument`・`permission-denied`・`not-found`などの
/// Firebaseのエラーコード。
class AppFunctionsException implements Exception {
  AppFunctionsException({required this.code, this.message, this.details});

  final String code;
  final String? message;
  final Object? details;

  @override
  String toString() => 'AppFunctionsException($code, $message)';
}

class _SdkCallable implements AppCallable {
  _SdkCallable({required this.name, required this.region});

  final String name;
  final String region;

  @override
  Future<AppCallableResult> call([Object? parameters]) async {
    try {
      final result = await cf.FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable(name).call(parameters);
      return AppCallableResult(result.data);
    } on cf.FirebaseFunctionsException catch (e) {
      throw AppFunctionsException(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }
}

class _RestConfig {
  const _RestConfig({
    required this.client,
    required this.projectId,
    required this.idToken,
    required this.timeout,
  });

  final http.Client client;
  final String Function() projectId;
  final Future<String?> Function() idToken;
  final Duration timeout;
}

class _RestCallable implements AppCallable {
  _RestCallable({
    required this.region,
    required this.name,
    required this.config,
  });

  final String region;
  final String name;
  final _RestConfig config;

  @override
  Future<AppCallableResult> call([Object? parameters]) async {
    final url = Uri.https(
      '$region-${config.projectId()}.cloudfunctions.net',
      '/$name',
    );
    final token = await config.idToken();
    final http.Response response;
    try {
      response = await config.client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': parameters}),
          )
          .timeout(config.timeout);
    } on TimeoutException {
      throw AppFunctionsException(
        code: 'deadline-exceeded',
        message: 'DEADLINE_EXCEEDED',
      );
    } on SocketException catch (e) {
      throw AppFunctionsException(code: 'unavailable', message: e.message);
    } on http.ClientException catch (e) {
      throw AppFunctionsException(code: 'unavailable', message: e.message);
    }

    final Object? body = _decodeBody(response);
    final map = body is Map ? body : null;
    final error = map?['error'];
    if (error is Map) {
      throw AppFunctionsException(
        code: _codeFromStatus(error['status'] as String?, response.statusCode),
        message: error['message'] as String?,
        details: error['details'],
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = _codeFromStatus(null, response.statusCode);
      throw AppFunctionsException(code: code, message: code.toUpperCase());
    }
    if (map == null ||
        !(map.containsKey('result') || map.containsKey('data'))) {
      throw AppFunctionsException(
        code: 'internal',
        message: 'Response is missing data field.',
      );
    }
    return AppCallableResult(
      map.containsKey('result') ? map['result'] : map['data'],
    );
  }

  static Object? _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// `INVALID_ARGUMENT`のようなgRPC形式のstatusを、`invalid-argument`の形のコードへ直す。
  /// statusが無い場合は、HTTPのステータスコードから決める。
  static String _codeFromStatus(String? status, int httpStatus) {
    if (status != null && status.isNotEmpty) {
      return status.toLowerCase().replaceAll('_', '-');
    }
    return switch (httpStatus) {
      400 => 'invalid-argument',
      401 => 'unauthenticated',
      403 => 'permission-denied',
      404 => 'not-found',
      409 => 'aborted',
      429 => 'resource-exhausted',
      499 => 'cancelled',
      501 => 'unimplemented',
      503 => 'unavailable',
      504 => 'deadline-exceeded',
      _ => 'internal',
    };
  }
}
