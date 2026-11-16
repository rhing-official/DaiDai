import 'dart:typed_data';

import 'bgm_import_source.dart';

/// Web以外ではBGMを使えない。
Future<List<BgmImportFile>> pickBgmFolder() async => const [];

/// Web以外では長さを調べない。
Future<Duration?> probeBgmDuration(Uint8List bytes, String mimeType) async =>
    null;

/// Web以外では画像を選ばせない。
Future<Uint8List?> pickBgmImage() async => null;

/// Web以外では縮小しない。
Future<Uint8List?> shrinkBgmCover(Uint8List bytes, {int size = 64}) async =>
    null;
