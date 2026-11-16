import 'dart:typed_data';

import '../../../utils/text_normalize.dart';

/// 端末内に登録したBGMの曲（2026-11-03）。バイト列は[BgmStorage]が持ち、ここはメタ情報だけ。
class BgmTrack {
  const BgmTrack({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    this.albumId,
    this.order = 0,
    this.hasCover = false,
    this.artist,
    this.tagAlbum,
    this.trackNo,
    this.discNo,
    this.durationMs,
    this.favorite = false,
  });

  final String id;

  /// 表示名（拡張子を除いたファイル名）。
  final String name;
  final String mimeType;
  final int size;

  /// 入っているアルバム（どのアルバムにも入れていなければnull、2026-11-15追加）。
  final String? albumId;

  /// 並び順（小さいほど先）。追加時は追加した時刻（末尾に付く）、並べ替えで0からの連番になる。
  final int order;

  /// 埋め込みのジャケット画像を保存しているか（画像は[BgmStorage.cover]で取る、2026-11-15追加）。
  final bool hasCover;

  /// ファイルのタグ（2026-11-15追加、無ければnull）。[tagAlbum]は、アプリのアルバム（[albumId]）とは別。
  final String? artist;
  final String? tagAlbum;
  final int? trackNo;

  /// ディスク番号（タグ、または`Disc 2`のようなディレクトリ名から。無ければnull＝Disc 1扱い）。
  final int? discNo;

  /// 曲の長さ（ミリ秒、分からなければnull）。
  final int? durationMs;

  /// お気に入りか（2026-11-15追加）。
  final bool favorite;

  BgmTrack copyWith({
    String? Function()? albumId,
    int? order,
    bool? favorite,
  }) => BgmTrack(
    id: id,
    name: name,
    mimeType: mimeType,
    size: size,
    albumId: albumId != null ? albumId() : this.albumId,
    order: order ?? this.order,
    hasCover: hasCover,
    artist: artist,
    tagAlbum: tagAlbum,
    trackNo: trackNo,
    discNo: discNo,
    durationMs: durationMs,
    favorite: favorite ?? this.favorite,
  );
}

/// 曲をまとめるアルバム（2026-11-15追加）。端末内だけにあり、サーバーには送らない。
class BgmAlbum {
  const BgmAlbum({required this.id, required this.name});

  final String id;
  final String name;
}

/// 曲の保存先（端末内）。Webは`IndexedDB`、それ以外は未対応で何も保存しない。
abstract class BgmStorage {
  Future<List<BgmTrack>> list();
  Future<List<BgmAlbum>> listAlbums();
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
  });
  Future<Uint8List?> bytes(String id);

  /// ジャケット画像（無ければnull）。
  Future<Uint8List?> cover(String id);

  /// ジャケット画像を後から保存する（追加時に無かった曲を、再生した時に読み取れた場合）。
  Future<void> setCover(String id, Uint8List cover);
  Future<void> remove(String id);
  Future<BgmAlbum> addAlbum(String name);
  Future<void> renameAlbum(String id, String name);

  /// アルバムを消す。中の曲は消さず、アルバムなしに戻す。
  Future<void> removeAlbum(String id);

  /// 取り込み直した時に、既にある曲の分類・タグだけを新しい値に更新する（曲・ジャケットはそのまま）。
  Future<void> updateTrackMeta(
    String id, {
    String? albumId,
    String? artist,
    String? tagAlbum,
    int? trackNo,
    int? discNo,
    int? order,
  });

  /// 曲を別のアルバムへ移す（nullで、アルバムなし）。
  Future<void> setTrackAlbum(String trackId, String? albumId);

  /// お気に入りの印を付ける／外す。
  Future<void> setFavorite(String trackId, bool favorite);

  /// 渡した曲の並びを、先頭から0,1,2…の並び順として保存する。
  Future<void> reorder(List<String> orderedTrackIds);

  /// 登録したアーティスト写真（アーティスト名→画像、2026-11-16）。
  Future<Map<String, Uint8List>> listArtistPhotos();

  /// [artist]の写真を保存する（nullで削除）。
  Future<void> setArtistPhoto(String artist, Uint8List? photo);
}

/// [tracks]から、[query]に合う曲だけを、元の並びのまま取り出す（2026-11-16、BGMの検索）。
/// 曲名に加えて、アーティスト・タグのアルバム名にも一致する。大文字小文字・ひらがな/カタカナの
/// ゆれは[normalizeForMatch]で吸収し、空白で区切った語は全て含む曲だけ（AND）。空の入力は全曲。
List<BgmTrack> searchBgmTracks(List<BgmTrack> tracks, String query) {
  final words = normalizeForMatch(
    query,
  ).split(RegExp(r'[\s\u3000]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return tracks;
  return [
    for (final t in tracks)
      if (_matchesAll(
        normalizeForMatch('${t.name} ${t.artist ?? ''} ${t.tagAlbum ?? ''}'),
        words,
      ))
        t,
  ];
}

bool _matchesAll(String haystack, List<String> words) =>
    words.every(haystack.contains);
