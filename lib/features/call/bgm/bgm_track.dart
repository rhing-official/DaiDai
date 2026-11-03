import 'dart:typed_data';

/// 端末内に登録したBGMの曲（2026-11-03）。バイト列は[BgmLibrary]が持ち、ここはメタ情報だけ。
class BgmTrack {
  const BgmTrack({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  final String id;

  /// 表示名（拡張子を除いたファイル名）。
  final String name;
  final String mimeType;
  final int size;
}

/// 曲の保存先（端末内）。Webは`IndexedDB`、それ以外は未対応で何も保存しない。
abstract class BgmStorage {
  Future<List<BgmTrack>> list();
  Future<BgmTrack> add({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  });
  Future<Uint8List?> bytes(String id);
  Future<void> remove(String id);
}
