import 'dart:typed_data';

/// クリップボードから貼り付けられたファイル（ブラウザの`paste`イベント経由）。
class PastedFile {
  const PastedFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}
