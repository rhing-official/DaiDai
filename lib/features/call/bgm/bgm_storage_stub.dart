import 'dart:typed_data';

import 'bgm_track.dart';

/// Web以外では未対応（何も保存しない）。
BgmStorage createBgmStorage() => _UnsupportedBgmStorage();

class _UnsupportedBgmStorage implements BgmStorage {
  @override
  Future<List<BgmTrack>> list() async => const [];

  @override
  Future<BgmTrack> add({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) => throw UnsupportedError('BGMはWebのみ対応です');

  @override
  Future<Uint8List?> bytes(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}
