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

/// カスタム音源の保存先（2026-11-13変更）。キャッシュ領域はOSやユーザーの操作で消えて、
/// チャンネルの音が標準音になるため、アプリのサポート領域に置く。音源のURL毎に別ファイル。
Future<File> customNotificationSoundFile(String url) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/notification_sounds');
  await dir.create(recursive: true);
  return File('${dir.path}/custom_${customSoundKey(url)}.${_extensionOf(url)}');
}

/// 通知音としてアップロードされたカスタム音源（Firebase StorageのURL）を、
/// Android通知チャンネルから参照出来る状態に整える（2026-09-06追加）。
///
/// 手順: (1)ダウンロード (2)サポート領域の`notification_sounds/custom_<キー>.<ext>`へ保存
/// (3)FileProvider経由でcontent:// URIを取得 (4)そのURIで、URL毎の新しいIDの
/// チャンネルを作る (5)古いカスタム音のチャンネル・ファイルを消す。
/// 同じIDの削除→再作成をしない（Androidが古い音を復元するため、2026-11-13変更）。
///
/// [url]で既に準備済み（かつファイルが実在する）なら何もしない。失敗した時は準備済みを
/// 記録しない（通知は標準プリセットで鳴り、次の呼び出しで再試行する）。
Future<void> ensureCustomNotificationChannelReady(String url) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final existing = await customNotificationSoundFile(url);
  if (prefs.getString(_readyUrlPrefsKey) == url && await existing.exists()) {
    return;
  }

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return;
    final file = existing;
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
    final channelId = androidCustomNotificationChannelIdFor(url);
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        'メッセージ（カスタム音）',
        description: '新着メッセージの通知（アップロードした音源）',
        importance: Importance.high,
        sound: UriAndroidNotificationSound(contentUri),
      ),
    );

    await prefs.setString(_readyUrlPrefsKey, url);
    await _removeOldCustomChannelsAndFiles(
      android,
      keepChannelId: channelId,
      keepFile: file,
    );
  } catch (_) {
    // 失敗しても通知自体は標準プリセットで鳴る
    // （push_notifications.dartの`_resolveAndroidChannel`参照）ため、ここでは無視して
    // 次回の呼び出し（再選択・次回起動時）に再試行する。
  }
}

/// 新しいチャンネルができた後で、古いカスタム音のチャンネル（旧版の固定IDを含む）と
/// ファイルを片付ける。
Future<void> _removeOldCustomChannelsAndFiles(
  AndroidFlutterLocalNotificationsPlugin? android, {
  required String keepChannelId,
  required File keepFile,
}) async {
  try {
    final channels = await android?.getNotificationChannels() ?? const [];
    for (final channel in channels) {
      if (channel.id.startsWith(androidCustomNotificationChannelId) &&
          channel.id != keepChannelId) {
        await android?.deleteNotificationChannel(channelId: channel.id);
      }
    }
    await for (final entity in keepFile.parent.list()) {
      if (entity is File && entity.path != keepFile.path) {
        await entity.delete();
      }
    }
  } catch (_) {
    // 片付けの失敗は無視する（音には影響しない）。
  }
}

String _extensionOf(String url) {
  final path = Uri.parse(url).path;
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1) return 'mp3';
  return path.substring(dotIndex + 1);
}
