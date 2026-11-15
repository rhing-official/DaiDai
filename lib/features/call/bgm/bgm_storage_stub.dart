import 'dart:typed_data';

import 'bgm_track.dart';

/// Web以外では未対応（何も保存しない）。
BgmStorage createBgmStorage() => _UnsupportedBgmStorage();

class _UnsupportedBgmStorage implements BgmStorage {
  @override
  Future<List<BgmTrack>> list() async => const [];

  @override
  Future<List<BgmAlbum>> listAlbums() async => const [];

  @override
  Future<BgmTrack> add({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    String? albumId,
    Uint8List? cover,
    String? artist,
    String? tagAlbum,
    int? trackNo,
    int? discNo,
    int? durationMs,
  }) => throw UnsupportedError('BGMはWebのみ対応です');

  @override
  Future<Uint8List?> bytes(String id) async => null;

  @override
  Future<Uint8List?> cover(String id) async => null;

  @override
  Future<void> setCover(String id, Uint8List cover) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  Future<BgmAlbum> addAlbum(String name) =>
      throw UnsupportedError('BGMはWebのみ対応です');

  @override
  Future<void> renameAlbum(String id, String name) async {}

  @override
  Future<void> removeAlbum(String id) async {}

  @override
  Future<void> updateTrackMeta(
    String id, {
    String? albumId,
    String? artist,
    String? tagAlbum,
    int? trackNo,
    int? discNo,
    int? order,
  }) async {}

  @override
  Future<void> setTrackAlbum(String trackId, String? albumId) async {}

  @override
  Future<void> setFavorite(String trackId, bool favorite) async {}

  @override
  Future<void> reorder(List<String> orderedTrackIds) async {}
}
