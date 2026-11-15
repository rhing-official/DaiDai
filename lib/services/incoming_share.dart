import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:share_handler/share_handler.dart';

/// OSの共有メニューからDaiDaiへ渡された内容の1件（2026-11-15）。
class IncomingShare {
  const IncomingShare({this.text, this.files = const []});

  /// 共有された文字（URL含む）。
  final String? text;
  final List<IncomingSharedFile> files;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && files.isEmpty;
}

class IncomingSharedFile {
  const IncomingSharedFile({
    required this.path,
    required this.name,
    required this.contentType,
  });

  final String path;
  final String name;

  /// 添付の種別（`image`・`video`・`file`）。
  final String contentType;
}

/// 共有メニューからの受け取り。Android（と将来のiOS）だけ。Webは別の経路（URLの
/// 引数）で受ける。それ以外では何も流れない。
class IncomingShareService {
  /// 共有を受け取れる環境か（Web・Android・iOS）。
  bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Webの共有ターゲット（インストールしたPWAが、OSの共有メニューに出る）から開かれた時の
  /// 文字・URL。`manifest.json`の`share_target`が`share_title`・`share_text`・`share_url`の
  /// 引数で渡す。ファイルは対象外（文字だけ）。
  IncomingShare? _fromWebUrl() {
    final q = Uri.base.queryParameters;
    final parts = [
      for (final key in ['share_title', 'share_text', 'share_url'])
        if ((q[key] ?? '').trim().isNotEmpty) q[key]!.trim(),
    ];
    if (parts.isEmpty) return null;
    // 文字とURLが同じ内容なら重ねない。
    final unique = <String>[];
    for (final p in parts) {
      if (!unique.any((u) => u.contains(p))) unique.add(p);
    }
    return IncomingShare(text: unique.join('\n'));
  }

  /// アプリが共有で起動された時の内容（無ければnull）。
  Future<IncomingShare?> initial() async {
    if (kIsWeb) return _fromWebUrl();
    if (!supported) return null;
    try {
      final media = await ShareHandlerPlatform.instance.getInitialSharedMedia();
      return media == null ? null : _convert(media);
    } catch (e) {
      debugPrint('[incomingShare] initial failed: $e');
      return null;
    }
  }

  /// アプリを開いている間に共有された内容。
  Stream<IncomingShare> stream() {
    if (kIsWeb || !supported) return const Stream.empty();
    return ShareHandlerPlatform.instance.sharedMediaStream
        .map(_convert)
        .where((s) => !s.isEmpty);
  }

  IncomingShare _convert(SharedMedia media) {
    final files = <IncomingSharedFile>[];
    for (final a in media.attachments ?? const <SharedAttachment?>[]) {
      if (a == null) continue;
      final name = a.path.split('/').last;
      files.add(
        IncomingSharedFile(
          path: a.path,
          name: name,
          contentType: switch (a.type) {
            SharedAttachmentType.image => 'image',
            SharedAttachmentType.video => 'video',
            _ => 'file',
          },
        ),
      );
    }
    return IncomingShare(text: media.content, files: files);
  }
}
