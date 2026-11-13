import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'models/message_time_format.dart';
import 'models/sound_preset.dart';
import 'router/app_router.dart' show globalBackStack, globalRouter;
import 'utils/message_time.dart';
import 'utils/android_notification_sound_sync.dart'
    show customNotificationSoundFile;

/// プッシュ通知（FCM）のAndroid側ローカル表示・バックグラウンドハンドラを
/// まとめたトップレベルの仕組み（2026-08-31追加）。今回の実装範囲は
/// Web + Androidのみ（`lib/repositories/push_notification_repository.dart`
/// 参照）。Web版は`web/firebase-messaging-sw.js`側で通知を組み立てて
/// 表示する為、このファイルの`showRemoteMessageNotification`は
/// Androidでのみ動作する（`kIsWeb`ガード）。
///
/// Cloud Functions（`functions/src/pushNotifications.ts`）はAndroid向けに
/// data-onlyメッセージを送る（Androidの通知アイコン/画像はローカル
/// アセットかバイト列でしか渡せず、リモートURLを直接指定出来ない為）。
/// このファイルが`http`でアイコン・プレビュー画像を取得し、
/// `flutter_local_notifications`でリッチ通知として組み立てる。
final _localNotifications = FlutterLocalNotificationsPlugin();

/// 通知音プリセット毎の通知チャンネル定義（既定は`SoundCategory.
/// notification.defaultPreset`、2026-09-06 Phase B追加）。Android通知チャンネルは
/// 作成後に音を変更出来ない為、プリセット毎に別チャンネルを用意し、
/// [_resolveAndroidChannelId]で表示時にどれを使うか切り替える（カスタム
/// アップロード音源用のチャンネルは`android_notification_sound_sync.dart`が
/// 選択・アップロードのタイミングで別途作成する）。
final _notificationChannels = {
  for (final preset in SoundCategory.notification.presets)
    preset.id: AndroidNotificationChannel(
      androidNotificationChannelIdFor(preset.id),
      'メッセージ（${_channelLabelFor(preset.id)}）',
      description: '新着メッセージの通知',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound(preset.id),
    ),
};

String _channelLabelFor(String presetId) => switch (presetId) {
  'notification_lasomarie' => 'チャイム',
  'notification_message_pop' => 'ポップ',
  'notification_happy_bells' => 'ハッピー',
  _ => presetId,
};

/// main()から一度だけ呼ぶ。Android通知チャンネルの作成・初期化に加え、
/// 通知タップ検知（[onDidReceiveNotificationResponse]）を登録する
/// （2026-09-02追加）。Androidはdata-onlyメッセージのみでOS自身は通知を
/// 表示しない為、FCMの`onMessageOpenedApp`/`getInitialMessage`では
/// タップを検知出来ず、自前で表示した`flutter_local_notifications`側の
/// コールバックが唯一の検知経路になる（アプリ起動中・バックグラウンドで
/// エンジンが生きている間のタップはこちらで拾える。完全終了状態からの
/// 起動＝cold startは[consumeLaunchNotificationPayload]で別途扱う）。
/// `flutter_local_notifications`の初期化がAndroid向けの設定だけで足りないWindows、および
/// 通知機能の対象外のLinuxでは、通知まわりの処理を行わない（2026-11-12）。
bool get _localNotificationsUnavailable =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

Future<void> initializeLocalNotifications() async {
  if (kIsWeb || _localNotificationsUnavailable) return;
  final android = _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  for (final channel in _notificationChannels.values) {
    await android?.createNotificationChannel(channel);
  }
  await _localNotifications.initialize(
    settings: const InitializationSettings(
      android: // 通知の小アイコンは白いシルエット（`drawable-*/ic_notification.png`、単色版の絵から作成、
          // 2026-11-12）。アダプティブアイコンの`@mipmap/ic_launcher`は小アイコンに使えない。
          AndroidInitializationSettings('ic_notification'),
    ),
    onDidReceiveNotificationResponse: (response) {
      if (kDebugMode) {
        debugPrint('[DIAG-TAP] response payload=${response.payload}');
      }
      navigateFromNotificationPayload(response.payload);
    },
  );
}

/// cold start（アプリ完全終了状態からの起動）で通知タップにより起動された
/// 場合、その通知のpayloadを返す（それ以外はnull）。`main()`が`runApp`の後、
/// 最初のフレーム描画後に呼び、[globalRouter]が確実に埋まった状態で
/// [navigateFromNotificationPayload]へ渡す（2026-09-02追加）。
Future<String?> consumeLaunchNotificationPayload() async {
  if (kIsWeb || _localNotificationsUnavailable) return null;
  final details = await _localNotifications.getNotificationAppLaunchDetails();
  if (kDebugMode) {
    debugPrint(
      '[DIAG-TAP] launchDetails didLaunch=${details?.didNotificationLaunchApp} '
      'payload=${details?.notificationResponse?.payload}',
    );
  }
  if (details?.didNotificationLaunchApp != true) return null;
  return details?.notificationResponse?.payload;
}

/// 通知タップ時のディープリンク先へ遷移する（2026-09-02追加）。
/// [showRemoteMessageNotification]が積んだpayload（`isDm`/`conversationId`/
/// `roomId`のJSON）を`app_router.dart`の`/chat/dm/:dmId`・
/// `/chat/group/:groupId`（[NotificationChatOpener]参照）へのURLに変換する。
void navigateFromNotificationPayload(String? payload) {
  if (kDebugMode) {
    debugPrint(
      '[DIAG-TAP] navigate payload=$payload router=${globalRouter != null}',
    );
  }
  if (payload == null) return;
  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final isDm = data['isDm'] as bool? ?? true;
    final conversationId = data['conversationId'] as String?;
    if (conversationId == null || conversationId.isEmpty) return;
    final roomId = data['roomId'] as String?;
    final path = isDm
        ? '/chat/dm/$conversationId'
        : '/chat/group/$conversationId';
    // 遷移が「戻る操作」として横取りされ中止されないようにする。
    globalBackStack?.bypassGuardsBriefly();
    globalRouter?.go(
      roomId != null && roomId.isNotEmpty ? '$path?roomId=$roomId' : path,
    );
  } catch (_) {
    // 壊れたpayload（古いバージョンの通知が残っていた等）は無視する。
  }
}

/// data-onlyの[RemoteMessage]から、語らいのアイコン・名前・メッセージ本文、
/// （スタンプ/動画の場合は）プレビュー画像付きの通知を組み立てて表示する。
/// フォアグラウンド（`FirebaseMessaging.onMessage`）・バックグラウンド
/// （[firebaseMessagingBackgroundHandler]）どちらからも呼ぶ共通処理。
Future<void> showRemoteMessageNotification(RemoteMessage message) async {
  if (kIsWeb) return;
  // 通話の着信・取消しは、ネイティブ側（`CallNotificationReceiver`、CallStyleの着信通知）が
  // 扱う（2026-11-12）。ここで通常の通知を重ねて出さない。
  if (isCallPushMessage(message.data)) return;
  try {
    await _showRemoteMessageNotification(message);
    if (kDebugMode) debugPrint('[DIAG-PUSH] notification shown');
  } catch (e, st) {
    if (kDebugMode) debugPrint('[DIAG-PUSH] show failed: $e\n$st');
    rethrow;
  }
}

Future<void> _showRemoteMessageNotification(RemoteMessage message) async {
  final data = message.data;
  final title = data['title'] as String? ?? '';
  final rawBody = data['body'] as String? ?? '';
  // 本文の先頭に送信時刻を付ける（2026-10-11追加）。表示時点の端末の現在時刻と
  // 比べて、日を跨いだら日付、年を跨いだら西暦4桁の年も付ける。OS標準の時刻
  // 表示との二重表示を避けるため`showWhen: false`にしている。
  final sentAtMs = int.tryParse(data['sentAt'] as String? ?? '');
  var body = rawBody;
  if (sentAtMs != null) {
    final prefs = await SharedPreferences.getInstance();
    final timeFormat = MessageTimeFormat.fromName(
      prefs.getString('messageTimeFormat'),
    );
    final label = formatNotificationTime(
      DateTime.fromMillisecondsSinceEpoch(sentAtMs),
      DateTime.now(),
      timeFormat,
    );
    body = '$label｜$rawBody';
  }
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

  final channel = await _resolveAndroidChannel();
  await _localNotifications.show(
    id: message.hashCode,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        largeIcon: largeIcon,
        styleInformation: styleInformation,
        showWhen: false,
      ),
    ),
    // タップ時に該当の語らいまで開くためのディープリンク情報
    // （2026-09-02追加、`navigateFromNotificationPayload`参照）。
    payload: jsonEncode({
      'isDm': (data['isDm'] as String?) == 'true',
      'conversationId': data['conversationId'] as String?,
      'roomId': data['roomId'] as String?,
    }),
  );
}

/// 現在選択されている通知音（`SharedPreferences`の`notificationSound`
/// キー、`notificationSoundProvider`と同じ永続化）に応じて表示すべき
/// 通知チャンネルを解決する（2026-09-06 Phase B追加）。バックグラウンド
/// isolateから呼ばれるためRiverpodの`ref`は使えず、`SharedPreferences`を
/// 直接読む。カスタムアップロード音源が選択されていても、まだ端末側の
/// ダウンロード・チャンネル作成（`ensureCustomNotificationChannelReady`）が
/// 完了していなければ標準プリセットにフォールバックする。
Future<AndroidNotificationChannel> _resolveAndroidChannel() async {
  final standard =
      _notificationChannels[SoundCategory.notification.defaultPreset.id]!;
  final prefs = await SharedPreferences.getInstance();
  // 背景のisolateは古い設定を持ち続けることがあるため、読む前に取り直す（2026-11-13）。
  await prefs.reload();
  final selected = prefs.getString('notificationSound');
  if (selected == null) return standard;
  if (selected.startsWith('http')) {
    final readyUrl = prefs.getString('notificationSoundCustomChannelReadyUrl');
    // 音ファイルが消えている時は、音なしのチャンネルを自動作成させず標準プリセットで鳴らす。
    if (readyUrl == selected &&
        await (await customNotificationSoundFile(selected)).exists()) {
      return AndroidNotificationChannel(
        androidCustomNotificationChannelIdFor(selected),
        'メッセージ（カスタム音）',
        description: '新着メッセージの通知（アップロードした音源）',
        importance: Importance.high,
      );
    }
    return standard;
  }
  return _notificationChannels[selected] ?? standard;
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
  if (kDebugMode) debugPrint('[DIAG-PUSH] background message received');
  await showRemoteMessageNotification(message);
}

/// 通話の着信・取消しのプッシュか（2026-11-12）。Android側の`CallNotificationReceiver`が
/// 着信通知（CallStyle）として表示・取消しするため、Dart側では通常の通知にしない。
bool isCallPushMessage(Map<String, dynamic> data) {
  final type = data['type'];
  return type == 'incoming_call' ||
      type == 'incoming_group_call' ||
      type == 'call_cancel';
}
