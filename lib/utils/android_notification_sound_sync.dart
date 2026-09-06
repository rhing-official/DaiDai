import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sound_preset.dart';

const _readyUrlPrefsKey = 'notificationSoundCustomChannelReadyUrl';

/// `android/app/src/main/kotlin/jp/rhing/daidai/MainActivity.kt`が公開する
/// FileProvider経由のcontent:// URI発行メソッドを呼ぶためのチャンネル。
const _fileProviderChannel = MethodChannel(
  'jp.rhing.daidai/notification_sound',
);

/// 通知音としてアップロードされたカスタム音源（Firebase StorageのURL）を、
/// Android通知チャンネルから参照できる状態に整える（2026-09-06追加）。
///
/// 手順: (1)ダウンロード (2)アプリのキャッシュディレクトリ配下
/// `notification_sounds/custom.<ext>`へ保存（再アップロード時は上書き）
/// (3)FileProvider経由でcontent:// URIを取得 (4)そのURIで
/// [androidCustomNotificationChannelId]チャンネルを作り直す。
///
/// [url]と同じ値で既に準備済みなら何もしない。`notificationSoundProvider`の
/// `setSound`/`syncFromRemote`、およびアプリ起動時（他端末で既にアップロード
/// 済みの設定が同期されてきた場合に備える）の両方から呼ぶ想定。
Future<void> ensureCustomNotificationChannelReady(String url) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_readyUrlPrefsKey) == url) return;

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return;

    final cacheDir = await getApplicationCacheDirectory();
    final soundsDir = Directory('${cacheDir.path}/notification_sounds');
    await soundsDir.create(recursive: true);
    final file = File('${soundsDir.path}/custom.${_extensionOf(url)}');
    await file.writeAsBytes(response.bodyBytes, flush: true);

    final contentUri = await _fileProviderChannel.invokeMethod<String>(
      'getContentUri',
      {'path': file.path},
    );
    if (contentUri == null) return;

    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.deleteNotificationChannel(
      channelId: androidCustomNotificationChannelId,
    );
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        androidCustomNotificationChannelId,
        'メッセージ（カスタム音）',
        description: '新着メッセージの通知（アップロードした音源）',
        importance: Importance.high,
        sound: UriAndroidNotificationSound(contentUri),
      ),
    );

    await prefs.setString(_readyUrlPrefsKey, url);
  } catch (_) {
    // 失敗しても通知自体は既定チャンネルにフォールバックする
    // （push_notifications.dartの`_resolveAndroidChannelId`参照）ため、
    // ここでは無視して次回の呼び出し（再選択・次回起動時）に委ねる。
  }
}

String _extensionOf(String url) {
  final path = Uri.parse(url).path;
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1) return 'mp3';
  return path.substring(dotIndex + 1);
}
