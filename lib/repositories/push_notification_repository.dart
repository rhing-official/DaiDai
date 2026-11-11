import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

  Future<void> _addToken(String userId, FcmTokenEntry entry) =>
      _tokenDoc(userId).set({
        'tokens': FieldValue.arrayUnion([entry.toJson()]),
      }, SetOptions(merge: true));

  static bool get _supportedPlatform => kIsWeb || Platform.isAndroid;
  static String get _platformName => kIsWeb ? 'web' : 'android';

  @override
  Future<bool> requestPermissionAndRegister(String userId) async {
    if (!_supportedPlatform) return false;

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return false;
    }

    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? _webPushVapidKey : null,
    );
    if (token == null) return false;

    await _addToken(
      userId,
      FcmTokenEntry(token: token, platform: _platformName),
    );
    return true;
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

  @override
  Future<void> unregisterCurrentToken(String userId) async {
    if (!_supportedPlatform) return;
    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? _webPushVapidKey : null,
    );
    if (token == null) return;
    await _tokenDoc(userId).set({
      'tokens': FieldValue.arrayRemove([
        FcmTokenEntry(token: token, platform: _platformName).toJson(),
      ]),
    }, SetOptions(merge: true));
  }
}
