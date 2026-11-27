import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../models/fcm_token_entry.dart';

/// Web Push証明書（VAPIDキー）。Firebase Console（`rhing.official@gmail.com`）
/// →プロジェクト設定→Cloud Messaging→「ウェブ構成」→「ウェブプッシュ証明書」で
/// 生成した公開鍵に差し替えること。未設定のままだとWeb版のみ`getToken`が
/// 失敗し通知登録がスキップされる（Androidには影響しない）。
const _webPushVapidKey =
    'BBkS0DXxCkc42-XU7q5D9C1jhx-PIYgj6nYVS5QBshGtozcdybnlJx4EQTec7aQLjzcfZAuTaDfMa6_ZOe8zlIQ';

/// プッシュ通知（FCM）のトークン登録を扱うリポジトリ。今回の実装範囲は
/// Web（デスクトップブラウザ）+ Androidのみ（iOS/macOSはApple Developer
/// Program未加入、Windows/Linuxは`firebase_messaging`が非対応のため対象外、
/// 2026-08-31）。トークンの保存先は`users/{uid}/private/fcm`（本人のみ読み書き、
/// 2026-11-07。以前は`users/{uid}.fcmTokens`で、全ログイン者が他人の端末トークンを
/// 読めたため移した）。
abstract class PushNotificationRepository {
  /// 通知権限をリクエストし、許可されればFCMトークンを取得して
  /// [userId]の`private/fcm`に登録する。対応外プラットフォーム（iOS/macOS/
  /// Windows/Linux）では何もしない。戻り値は実際に許可されFCMトークンの
  /// 登録まで完了したか（2026-09-01、設定タブのトグルUIが結果を表示に
  /// 反映出来るよう`Future<void>`から変更）。
  Future<bool> requestPermissionAndRegister(String userId);

  /// トークンが更新された際、新トークンを[userId]に再登録する。
  Stream<String> onTokenRefresh(String userId);

  /// ログアウト時等に、この端末のトークンを[userId]から削除する。
  Future<void> unregisterCurrentToken(String userId);

  /// この端末で、[userId]宛ての通知を止めているか（2026-11-27）。トークンが無い、
  /// 対応外のプラットフォーム、取得できない場合は`false`（止めていない）。
  Future<bool> isCurrentDeviceMuted(String userId);

  /// この端末で、[userId]宛ての通知を止める・止めない。サーバーが、止めているトークンへは
  /// 送らない。トークンが無い時に止める場合は、止めた状態のトークンを作る（後で許可を
  /// 取って登録し直しても、止めたまま）。対応外のプラットフォームでは何もしない。
  Future<void> setCurrentDeviceMuted(String userId, bool muted);
}

class FirebaseMessagingPushNotificationRepository
    implements PushNotificationRepository {
  FirebaseMessagingPushNotificationRepository({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;

  DocumentReference<Map<String, dynamic>> _tokenDoc(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('private')
      .doc('fcm');

  /// ルールの上限（`private/fcm`のtokensは10件まで）。
  static const _maxTokens = 10;

  /// トークンを登録する。すでにあれば何もしない。上限に達していたら、古い（先頭の）
  /// ものから外して入れる（2026-11-12）。以前は`arrayUnion`で足すだけだったため、
  /// 端末の入れ替え・再インストール・トークン更新で溜まった古いトークンが10件に達すると、
  /// 以降の登録がルールで拒否され（permission-denied）、その端末に通知が一切届かなく
  /// なっていた。
  Future<void> _addToken(String userId, FcmTokenEntry entry) {
    final doc = _tokenDoc(userId);
    return _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(doc);
      final current = <Map<String, dynamic>>[
        for (final e in (snap.data()?['tokens'] as List?) ?? const [])
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      if (current.any((e) => e['token'] == entry.token)) return;
      current.add(entry.toJson());
      final kept = current.length > _maxTokens
          ? current.sublist(current.length - _maxTokens)
          : current;
      transaction.set(doc, {'tokens': kept});
    });
  }

  static bool get _supportedPlatform => kIsWeb || Platform.isAndroid;
  static String get _platformName => kIsWeb ? 'web' : 'android';

  @override
  Future<bool> requestPermissionAndRegister(String userId) async {
    if (!_supportedPlatform) return false;

    // 診断ログ（debugのみ、2026-11-12。通知が届かない原因の切り分け用）。
    void diag(String message) {
      if (kDebugMode) debugPrint('[DIAG-PUSH] $message');
    }

    try {
      final settings = await _messaging.requestPermission();
      diag('permission=${settings.authorizationStatus}');
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }

      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? _webPushVapidKey : null,
      );
      diag(
        'token=${token == null ? 'null' : '${token.substring(0, 12)}…(${token.length})'}',
      );
      if (token == null) return false;

      await _addToken(
        userId,
        FcmTokenEntry(token: token, platform: _platformName),
      );
      diag('token saved platform=$_platformName');
      return true;
    } catch (e) {
      diag('register failed: $e');
      // 失敗の切り分け: 本人の`private/fcm`を読んで、件数と項目名だけ出す（トークンは出さない）。
      try {
        final snap = await _tokenDoc(userId).get();
        final data = snap.data();
        final tokens = data?['tokens'];
        diag(
          'fcm doc exists=${snap.exists} keys=${data?.keys.toList()} '
          'tokens=${tokens is List ? tokens.length : tokens.runtimeType}',
        );
      } catch (readError) {
        diag('fcm doc read failed: $readError');
      }
      rethrow;
    }
  }

  @override
  Stream<String> onTokenRefresh(String userId) {
    // Windows・Linuxには`firebase_messaging`の実装が無い（2026-11-12）。
    if (!_supportedPlatform) return const Stream<String>.empty();
    return _messaging.onTokenRefresh.asyncMap((token) async {
      await _addToken(
        userId,
        FcmTokenEntry(token: token, platform: _platformName),
      );
      return token;
    });
  }

  /// このドキュメントの`tokens`を読み、[change]で書き換えて保存する。[change]が`null`を
  /// 返したら書かない。
  Future<void> _updateTokens(
    String userId,
    List<Map<String, dynamic>>? Function(List<Map<String, dynamic>> current)
    change,
  ) {
    final doc = _tokenDoc(userId);
    return _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(doc);
      final current = <Map<String, dynamic>>[
        for (final e in (snap.data()?['tokens'] as List?) ?? const [])
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      final next = change(current);
      if (next == null) return;
      final kept = next.length > _maxTokens
          ? next.sublist(next.length - _maxTokens)
          : next;
      transaction.set(doc, {'tokens': kept});
    });
  }

  Future<String?> _currentToken() =>
      _messaging.getToken(vapidKey: kIsWeb ? _webPushVapidKey : null);

  @override
  Future<void> unregisterCurrentToken(String userId) async {
    if (!_supportedPlatform) return;
    final token = await _currentToken();
    if (token == null) return;
    // 止めている印（`muted`）が付いた登録は、`arrayRemove`の完全一致では消せない為、
    // トークンの文字列で外す（2026-11-27）。
    await _updateTokens(userId, (current) {
      final next = [
        for (final e in current)
          if (e['token'] != token) e,
      ];
      return next.length == current.length ? null : next;
    });
  }

  @override
  Future<bool> isCurrentDeviceMuted(String userId) async {
    if (!_supportedPlatform) return false;
    try {
      final token = await _currentToken();
      if (token == null) return false;
      final snap = await _tokenDoc(userId).get();
      for (final e in (snap.data()?['tokens'] as List?) ?? const []) {
        if (e is Map && e['token'] == token) return e['muted'] == true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[DIAG-PUSH] isCurrentDeviceMuted failed: $e');
      return false;
    }
  }

  @override
  Future<void> setCurrentDeviceMuted(String userId, bool muted) async {
    if (!_supportedPlatform) return;
    final token = await _currentToken();
    if (token == null) return;
    await _updateTokens(userId, (current) {
      final index = current.indexWhere((e) => e['token'] == token);
      if (index < 0) {
        // 登録が無い時に止めないなら、作らない。止めるなら、止めた状態で作る。
        if (!muted) return null;
        return [
          ...current,
          FcmTokenEntry(
            token: token,
            platform: _platformName,
            muted: true,
          ).toJson(),
        ];
      }
      if ((current[index]['muted'] == true) == muted) return null;
      final next = [...current];
      final entry = Map<String, dynamic>.from(next[index]);
      if (muted) {
        entry['muted'] = true;
      } else {
        entry.remove('muted');
      }
      next[index] = entry;
      return next;
    });
  }
}
