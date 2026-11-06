import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/message.dart';

/// メッセージの添付（ファイル・画像・動画、複数添付は全件）を共有する
/// （2026-10-31追加）。ファイルを取得してOSの共有シートへ渡す。Linuxは
/// 共有シートがファイルに未対応の為、取得したURLをブラウザ（外部アプリ）で
/// 開いてダウンロードにフォールバックする。取得・共有に失敗した場合も同様。
/// 添付の無いメッセージでは何もしない。
Future<void> shareMessageAttachments(Message message) {
  final items = message.attachments.isNotEmpty
      ? message.attachments
      : [if (message.fileMetadata != null) message.fileMetadata!];
  // 添付が無い本文だけのメッセージは、本文を共有シートへ渡す（2026-11-05）。
  if (items.isEmpty) return shareText(message.content);
  return shareFiles([
    for (final item in items)
      (url: item.url, name: item.fileName, mimeType: item.mimeType),
  ]);
}

/// 共有出来るメッセージか（添付がある、又は本文だけの通常のメッセージ）。
bool shareableMessage(Message message) =>
    message.fileMetadata != null ||
    message.attachments.isNotEmpty ||
    (message.contentType == 'text' && message.content.trim().isNotEmpty);

/// 本文を共有する。共有シートが使えない環境（Linux等）では何もしない。
Future<void> shareText(String text) async {
  if (text.trim().isEmpty) return;
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (e, st) {
    debugPrint('Failed to share text: $e\n$st');
  }
}

/// 手元のバイト列（ノートの`.md`・`.png`など）を共有シートへ渡す（2026-11-06）。共有シートが
/// 使えない環境（Linux等）や失敗した時はfalseを返す（呼び出し側が保存にフォールバックする）。
Future<bool> shareBytesFile({
  required Uint8List bytes,
  required String name,
  required String mimeType,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return false;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
      ),
    );
    return true;
  } catch (e, st) {
    debugPrint('Failed to share bytes: $e\n$st');
    return false;
  }
}

/// 共有するファイル1件（取得先URL・ファイル名・MIME）。
typedef ShareableFile = ({String url, String name, String? mimeType});

/// [items]を共有する（動作は[shareMessageAttachments]と同じ）。
Future<void> shareFiles(List<ShareableFile> items) async {
  if (items.isEmpty) return;

  Future<void> download() async {
    for (final item in items) {
      await launchUrl(
        Uri.parse(item.url),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    await download();
    return;
  }
  try {
    final files = <XFile>[];
    for (final item in items) {
      final response = await http.get(Uri.parse(item.url));
      if (response.statusCode != 200)
        throw StateError('HTTP ${response.statusCode}');
      files.add(
        XFile.fromData(
          response.bodyBytes,
          mimeType: item.mimeType,
          name: item.name,
        ),
      );
    }
    await SharePlus.instance.share(ShareParams(files: files));
  } catch (e, st) {
    debugPrint('Failed to share attachment: $e\n$st');
    await download();
  }
}
