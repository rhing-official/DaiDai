import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'bgm_import_source.dart';

/// ディレクトリを選ばせ、中の音声ファイル（サブディレクトリを含む）を返す。ブラウザの
/// `<input type=file webkitdirectory>`を使う。何も選ばなければ空。
Future<List<BgmImportFile>> pickBgmFolder() {
  final completer = Completer<List<BgmImportFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.onchange = ((web.Event _) {
    final files = input.files;
    final result = <BgmImportFile>[];
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file == null || !isBgmAudioFileName(file.name)) continue;
        // `a/b/c.mp3`のような相対パスの、ファイルより外側のディレクトリ名の並び（a, b）。
        final parts = file.webkitRelativePath.split('/');
        final folderPath = parts.length >= 2
            ? parts.sublist(0, parts.length - 1)
            : const <String>[];
        result.add(
          BgmImportFile(
            name: file.name,
            folderPath: folderPath,
            readBytes: () async {
              final buffer = await file.arrayBuffer().toDart;
              return buffer.toDart.asUint8List();
            },
          ),
        );
      }
    }
    completer.complete(result);
  }).toJS;
  // 何も選ばずに閉じた時（`cancel`）。
  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(const []);
  }).toJS;
  input.click();
  return completer.future;
}

/// 画像を1枚選ばせて、中身を返す（アーティスト写真用、2026-11-16）。何も選ばなければnull。
Future<Uint8List?> pickBgmImage() {
  final completer = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.onchange = ((web.Event _) async {
    final file = input.files?.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    try {
      final buffer = await file.arrayBuffer().toDart;
      completer.complete(buffer.toDart.asUint8List());
    } catch (_) {
      completer.complete(null);
    }
  }).toJS;
  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;
  input.click();
  return completer.future;
}

/// 曲の長さを、`<audio>`のメタデータから調べる（読めなければnull）。
Future<Duration?> probeBgmDuration(Uint8List data, String mimeType) async {
  final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final audio = web.HTMLAudioElement()..preload = 'metadata';
  final completer = Completer<Duration?>();
  void finish(Duration? d) {
    if (!completer.isCompleted) completer.complete(d);
  }

  audio.onloadedmetadata = ((web.Event _) {
    final d = audio.duration;
    finish(
      d.isFinite && d > 0 ? Duration(milliseconds: (d * 1000).round()) : null,
    );
  }).toJS;
  audio.onerror = ((web.Event _) => finish(null)).toJS;
  audio.src = url;
  try {
    return await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  } finally {
    audio.removeAttribute('src');
    audio.load();
    web.URL.revokeObjectURL(url);
  }
}

/// ジャケット画像を、相手へ送れるよう[size]px四方（中央を切り抜き）のJPEGへ縮める。失敗したらnull。
Future<Uint8List?> shrinkBgmCover(Uint8List bytes, {int size = 64}) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final image = web.HTMLImageElement();
  final loaded = Completer<bool>();
  image.onload = ((web.Event _) {
    if (!loaded.isCompleted) loaded.complete(true);
  }).toJS;
  image.onerror = ((web.Event _) {
    if (!loaded.isCompleted) loaded.complete(false);
  }).toJS;
  image.src = url;
  try {
    final ok = await loaded.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    if (!ok || image.naturalWidth == 0 || image.naturalHeight == 0) return null;
    final side = image.naturalWidth < image.naturalHeight
        ? image.naturalWidth
        : image.naturalHeight;
    final canvas = web.HTMLCanvasElement()
      ..width = size
      ..height = size;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.drawImage(
      image,
      (image.naturalWidth - side) / 2,
      (image.naturalHeight - side) / 2,
      side,
      side,
      0,
      0,
      size,
      size,
    );
    final dataUrl = canvas.toDataURL('image/jpeg', 0.7.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
