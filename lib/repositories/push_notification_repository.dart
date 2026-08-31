import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/fcm_token_entry.dart';
import 'user_repository.dart';

/// Web Push証明書（VAPIDキー）。Firebase Console（`rhing.official@gmail.com`）
/// →プロジェクト設定→Cloud Messaging→「ウェブ構成」→「ウェブプッシュ証明書」で
/// 生成した公開鍵に差し替えること。未設定のままだとWeb版のみ`getToken`が
/// 失敗し通知登録がスキップされる（Androidには影響しない）。
const _webPushVapidKey =
    'BBkS0DXxCkc42-XU7q5D9C1jhx-PIYgj6nYVS5QBshGtozcdybnlJx4EQTec7aQLjzcfZAuTaDfMa6_ZOe8zlIQ';

/// プッシュ通知（FCM）のトークン登録を扱うリポジトリ。今回の実装範囲は
/// Web（デスクトップブラウザ）+ Androidのみ（iOS/macOSはApple Developer
/// Program未加入、Windows/Linuxは`firebase_messaging`が非対応のため対象外、
/// 2026-08-31）。実際の永続化は[UserRepository.addToProfileList]/
/// [removeFromProfileList]に委譲する（`AppUser.fcmTokens`はその他の蔵の
/// リストと同じ配列フィールドのため、専用の書き込みメソッドを新設せず
/// 既存の汎用メソッドを再利用する）。
abstract class PushNotificationRepository {
  /// 通知権限をリクエストし、許可されればFCMトークンを取得して
  /// [userId]の`fcmTokens`に登録する。対応外プラットフォーム（iOS/macOS/
  /// Windows/Linux）では何もしない。
  Future<void> requestPermissionAndRegister(String userId);

  /// トークンが更新された際、新トークンを[userId]に再登録する。
  Stream<String> onTokenRefresh(String userId);

  /// ログアウト時等に、この端末のトークンを[userId]から削除する。
  Future<void> unregisterCurrentToken(String userId);
}

class FirebaseMessagingPushNotificationRepository
    implements PushNotificationRepository {
  FirebaseMessagingPushNotificationRepository({
    required this.userRepository,
    FirebaseMessaging? messaging,
  }) : _messaging = messaging ?? FirebaseMessaging.instance;

  final UserRepository userRepository;
  final FirebaseMessaging _messaging;

  static bool get _supportedPlatform => kIsWeb || Platform.isAndroid;
  static String get _platformName => kIsWeb ? 'web' : 'android';

  @override
  Future<void> requestPermissionAndRegister(String userId) async {
    if (!_supportedPlatform) return;

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return;
    }

    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? _webPushVapidKey : null,
    );
    if (token == null) return;

    await userRepository.addToProfileList(
      userId,
      'fcmTokens',
      FcmTokenEntry(token: token, platform: _platformName).toJson(),
    );
  }

  @override
  Stream<String> onTokenRefresh(String userId) {
    return _messaging.onTokenRefresh.asyncMap((token) async {
      await userRepository.addToProfileList(
        userId,
        'fcmTokens',
        FcmTokenEntry(token: token, platform: _platformName).toJson(),
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
    await userRepository.removeFromProfileList(
      userId,
      'fcmTokens',
      FcmTokenEntry(token: token, platform: _platformName).toJson(),
    );
  }
}
