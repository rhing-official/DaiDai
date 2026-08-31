import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

/// プッシュ通知（FCM）のAndroid側ローカル表示・バックグラウンドハンドラを
/// まとめたトップレベルの仕組み（2026-08-31追加）。今回の実装範囲は
/// Web + Androidのみ（`lib/repositories/push_notification_repository.dart`
/// 参照）。Web版は`web/firebase-messaging-sw.js`側で通知を組み立てて
/// 表示するため、このファイルの`showRemoteMessageNotification`は
/// Androidでのみ動作する（`kIsWeb`ガード）。
///
/// Cloud Functions（`functions/src/pushNotifications.ts`）はAndroid向けに
/// data-onlyメッセージを送る（Androidの通知アイコン/画像はローカル
/// アセットかバイト列でしか渡せず、リモートURLを直接指定できないため）。
/// このファイルが`http`でアイコン・プレビュー画像を取得し、
/// `flutter_local_notifications`でリッチ通知として組み立てる。
final _localNotifications = FlutterLocalNotificationsPlugin();

const _androidChannel = AndroidNotificationChannel(
  'daidai_messages',
  'メッセージ',
  description: '新着メッセージの通知',
  importance: Importance.high,
);

/// main()から一度だけ呼ぶ。Android通知チャンネルの作成・初期化を行う。
Future<void> initializeLocalNotifications() async {
  if (kIsWeb) return;
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_androidChannel);
  await _localNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

/// data-onlyの[RemoteMessage]から、語らいのアイコン・名前・メッセージ本文、
/// （スタンプ/動画の場合は）プレビュー画像付きの通知を組み立てて表示する。
/// フォアグラウンド（`FirebaseMessaging.onMessage`）・バックグラウンド
/// （[firebaseMessagingBackgroundHandler]）どちらからも呼ぶ共通処理。
Future<void> showRemoteMessageNotification(RemoteMessage message) async {
  if (kIsWeb) return;
  final data = message.data;
  final title = data['title'] as String? ?? '';
  final body = data['body'] as String? ?? '';
  final largeIconBytes = await _downloadBytes(data['iconUrl'] as String?);
  final previewBytes = await _downloadBytes(data['previewUrl'] as String?);

  final largeIcon = largeIconBytes != null
      ? ByteArrayAndroidBitmap(largeIconBytes)
      : null;
  final styleInformation = previewBytes != null
      ? BigPictureStyleInformation(
          ByteArrayAndroidBitmap(previewBytes),
          largeIcon: largeIcon,
          contentTitle: title,
          summaryText: body,
        )
      : null;

  await _localNotifications.show(
    id: message.hashCode,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        largeIcon: largeIcon,
        styleInformation: styleInformation,
      ),
    ),
  );
}

Future<Uint8List?> _downloadBytes(String? url) async {
  if (url == null || url.isEmpty) return null;
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

/// アプリ終了状態でプッシュ通知を受信した際にOSから起動されるトップレベルの
/// バックグラウンドハンドラ（Flutterの制約でトップレベル関数である必要が
/// あり、`@pragma('vm:entry-point')`必須）。`main()`の`Firebase.initializeApp`
/// 直後に`FirebaseMessaging.onBackgroundMessage`へ登録する。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await showRemoteMessageNotification(message);
}
