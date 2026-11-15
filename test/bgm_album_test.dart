import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:daidai/features/call/bgm/bgm_cover.dart';
import 'package:daidai/features/call/bgm/bgm_import_source.dart';
import 'package:daidai/features/call/bgm/bgm_now_playing.dart';
import 'package:daidai/features/call/bgm/bgm_queue.dart';
import 'package:daidai/features/call/bgm/bgm_track.dart';
import 'package:daidai/features/call/bgm/call_bgm.dart';
import 'package:flutter_test/flutter_test.dart';

/// メモリ上の偽のストレージ。
class _FakeStorage implements BgmStorage {
  final tracks = <String, BgmTrack>{};
  final albums = <String, BgmAlbum>{};
  int _n = 0;

  @override
  Future<List<BgmTrack>> list() async => tracks.values.toList();

  @override
  Future<List<BgmAlbum>> listAlbums() async => albums.values.toList();

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
  }) async {
    final id = 't${_n++}';
    final t = BgmTrack(
      id: id,
      name: name,
      mimeType: mimeType,
      size: bytes.length,
      albumId: albumId,
      order: _n,
      hasCover: cover != null,
      artist: artist,
      tagAlbum: tagAlbum,
      trackNo: trackNo,
      discNo: discNo,
      durationMs: durationMs,
    );
    if (cover != null) covers[id] = cover;
    tracks[id] = t;
    return t;
  }

  final covers = <String, Uint8List>{};

  @override
  Future<Uint8List?> cover(String id) async => covers[id];

  @override
  Future<void> setCover(String id, Uint8List cover) async {
    covers[id] = cover;
    tracks[id] = BgmTrack(
      id: id,
      name: tracks[id]!.name,
      mimeType: tracks[id]!.mimeType,
      size: tracks[id]!.size,
      albumId: tracks[id]!.albumId,
      order: tracks[id]!.order,
      hasCover: true,
    );
  }

  @override
  Future<Uint8List?> bytes(String id) async => Uint8List(1);

  @override
  Future<void> remove(String id) async => tracks.remove(id);

  @override
  Future<BgmAlbum> addAlbum(String name) async {
    final a = BgmAlbum(id: 'a${_n++}', name: name);
    albums[a.id] = a;
    return a;
  }

  @override
  Future<void> renameAlbum(String id, String name) async =>
      albums[id] = BgmAlbum(id: id, name: name);

  @override
  Future<void> removeAlbum(String id) async {
    albums.remove(id);
    for (final t in tracks.values.toList()) {
      if (t.albumId == id) tracks[t.id] = t.copyWith(albumId: () => null);
    }
  }

  @override
  Future<void> updateTrackMeta(
    String id, {
    String? albumId,
    String? artist,
    String? tagAlbum,
    int? trackNo,
    int? discNo,
    int? order,
  }) async {
    final t = tracks[id]!;
    tracks[id] = BgmTrack(
      id: id,
      name: t.name,
      mimeType: t.mimeType,
      size: t.size,
      albumId: albumId ?? t.albumId,
      order: order ?? t.order,
      hasCover: t.hasCover,
      artist: artist ?? t.artist,
      tagAlbum: tagAlbum ?? t.tagAlbum,
      trackNo: trackNo ?? t.trackNo,
      discNo: discNo ?? t.discNo,
      durationMs: t.durationMs,
    );
  }

  @override
  Future<void> setFavorite(String trackId, bool favorite) async =>
      tracks[trackId] = tracks[trackId]!.copyWith(favorite: favorite);

  @override
  Future<void> setTrackAlbum(String trackId, String? albumId) async =>
      tracks[trackId] = tracks[trackId]!.copyWith(albumId: () => albumId);

  @override
  Future<void> reorder(List<String> orderedTrackIds) async {
    for (var i = 0; i < orderedTrackIds.length; i++) {
      tracks[orderedTrackIds[i]] = tracks[orderedTrackIds[i]]!.copyWith(
        order: i,
      );
    }
  }
}

BgmTrack _t(String id, {int order = 0, String? albumId}) => BgmTrack(
  id: id,
  name: id,
  mimeType: 'audio/mpeg',
  size: 1,
  albumId: albumId,
  order: order,
);

void main() {
  group('nextBgmTrack', () {
    final queue = [_t('a'), _t('b'), _t('c')];

    test('順番: 次の曲、最後の次は先頭', () {
      expect(
        nextBgmTrack(
          queue: queue,
          current: queue[0],
          order: BgmPlayOrder.inOrder,
        )!.id,
        'b',
      );
      expect(
        nextBgmTrack(
          queue: queue,
          current: queue[2],
          order: BgmPlayOrder.inOrder,
        )!.id,
        'a',
      );
    });

    test('1曲リピート: 同じ曲', () {
      expect(
        nextBgmTrack(
          queue: queue,
          current: queue[1],
          order: BgmPlayOrder.repeatOne,
        )!.id,
        'b',
      );
    });

    test('シャッフル: 今の曲以外から選ぶ', () {
      for (var i = 0; i < 30; i++) {
        final next = nextBgmTrack(
          queue: queue,
          current: queue[1],
          order: BgmPlayOrder.shuffle,
          random: Random(i),
        )!;
        expect(next.id, isNot('b'));
      }
    });

    test('1曲だけなら、どの順序でもその曲を繰り返す', () {
      final one = [_t('x')];
      for (final order in BgmPlayOrder.values) {
        expect(
          nextBgmTrack(queue: one, current: one.first, order: order)!.id,
          'x',
        );
      }
    });

    test('空なら null', () {
      expect(
        nextBgmTrack(
          queue: const [],
          current: _t('a'),
          order: BgmPlayOrder.inOrder,
        ),
        isNull,
      );
    });
  });

  test('sortBgmTracks: 並び順→id', () {
    final sorted = sortBgmTracks([
      _t('b', order: 2),
      _t('a', order: 2),
      _t('c'),
    ]);
    expect([for (final t in sorted) t.id], ['c', 'a', 'b']);
  });

  group('CallBgm（アルバム）', () {
    late _FakeStorage storage;
    late CallBgm bgm;

    setUp(() {
      storage = _FakeStorage();
      bgm = CallBgm(
        storage: storage,
        micTrack: () => null,
        replaceOutgoingAudio: (_) async {},
        onPlayingChanged: (_) {},
      );
    });

    test('アルバムを作り、曲を入れ、並べ替え・移動・削除ができる', () async {
      await bgm.addAlbum('旅');
      final album = bgm.albums.single;
      await bgm.addTrack(
        name: 'one',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
        albumId: album.id,
      );
      await bgm.addTrack(
        name: 'two',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
        albumId: album.id,
      );
      await bgm.addTrack(
        name: 'free',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
      );
      expect([for (final t in bgm.tracksOf(album.id)) t.name], ['one', 'two']);
      expect(bgm.unclassifiedCount, 1);
      expect(bgm.tracksOf(null).length, 3);

      // 並べ替え
      await bgm.reorderTracks(bgm.tracksOf(album.id).reversed.toList());
      expect([for (final t in bgm.tracksOf(album.id)) t.name], ['two', 'one']);

      // アルバムへ移動
      final free = bgm.tracksOf(null).firstWhere((t) => t.name == 'free');
      await bgm.moveTrack(free, album.id);
      expect(bgm.tracksOf(album.id).length, 3);
      expect(bgm.unclassifiedCount, 0);

      // アルバムを消しても、曲は残る
      await bgm.removeAlbum(album.id);
      expect(bgm.albums, isEmpty);
      expect(bgm.tracksOf(null).length, 3);
      expect(bgm.unclassifiedCount, 3);
    });

    test('再生順は 順番→シャッフル→1曲リピート→順番 と切り替わる', () {
      expect(bgm.playOrder, BgmPlayOrder.inOrder);
      bgm.cyclePlayOrder();
      expect(bgm.playOrder, BgmPlayOrder.shuffle);
      bgm.cyclePlayOrder();
      expect(bgm.playOrder, BgmPlayOrder.repeatOne);
      bgm.cyclePlayOrder();
      expect(bgm.playOrder, BgmPlayOrder.inOrder);
    });
  });

  group('adjacentBgmTrack', () {
    final queue = [_t('a'), _t('b'), _t('c')];

    test('次へ・前へは一覧の隣（端で回る）。1曲リピートでも進む', () {
      expect(
        adjacentBgmTrack(
          queue: queue,
          current: queue[2],
          forward: true,
          order: BgmPlayOrder.repeatOne,
        )!.id,
        'a',
      );
      expect(
        adjacentBgmTrack(
          queue: queue,
          current: queue[0],
          forward: false,
          order: BgmPlayOrder.inOrder,
        )!.id,
        'c',
      );
    });

    test('シャッフルの次へは今の曲以外', () {
      for (var i = 0; i < 20; i++) {
        expect(
          adjacentBgmTrack(
            queue: queue,
            current: queue[1],
            forward: true,
            order: BgmPlayOrder.shuffle,
            random: Random(i),
          )!.id,
          isNot('b'),
        );
      }
    });
  });

  group('extractBgmCover', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

    Uint8List be32(int n) =>
        Uint8List.fromList([n >> 24, n >> 16 & 255, n >> 8 & 255, n & 255]);
    Uint8List syncsafe(int n) => Uint8List.fromList([
      n >> 21 & 127,
      n >> 14 & 127,
      n >> 7 & 127,
      n & 127,
    ]);

    test('mp3（ID3v2.3のAPIC）', () {
      // APICの本体: 文字コード0・MIME'image/jpeg'+0・種類3・説明''+0・画像
      final body = <int>[0, ...'image/jpeg'.codeUnits, 0, 3, 0, ...jpeg];
      final frame = <int>[
        ...'APIC'.codeUnits,
        ...be32(body.length),
        0,
        0,
        ...body,
      ];
      final tag = Uint8List.fromList([
        ...'ID3'.codeUnits,
        3,
        0,
        0,
        ...syncsafe(frame.length),
        ...frame,
        ...List.filled(20, 0),
      ]);
      final cover = extractBgmCover(tag)!;
      expect(cover.data, jpeg);
      expect(cover.mimeType, 'image/jpeg');
    });

    test('FLAC（PICTUREブロック）', () {
      final body = <int>[
        ...be32(3),
        ...be32(10),
        ...'image/jpeg'.codeUnits,
        ...be32(0),
        ...List.filled(16, 0),
        ...be32(jpeg.length),
        ...jpeg,
      ];
      final data = Uint8List.fromList([
        ...'fLaC'.codeUnits,
        0x80 | 6,
        body.length >> 16 & 255,
        body.length >> 8 & 255,
        body.length & 255,
        ...body,
      ]);
      expect(extractBgmCover(data)!.data, jpeg);
    });

    test('m4a（moov/udta/meta/ilst/covr）', () {
      Uint8List box(String type, List<int> body) => Uint8List.fromList([
        ...be32(8 + body.length),
        ...type.codeUnits,
        ...body,
      ]);
      final dataBox = box('data', [...be32(13), ...be32(0), ...jpeg]);
      final covr = box('covr', dataBox);
      final ilst = box('ilst', covr);
      final meta = box('meta', [0, 0, 0, 0, ...ilst]);
      final udta = box('udta', meta);
      final moov = box('moov', udta);
      final ftyp = box('ftyp', 'M4A '.codeUnits + [0, 0, 0, 0]);
      final file = Uint8List.fromList([...ftyp, ...moov]);
      expect(extractBgmCover(file)!.data, jpeg);
    });

    test('ジャケットが無い・壊れている・知らない形式は null（例外にしない）', () {
      expect(extractBgmCover(Uint8List(0)), isNull);
      expect(
        extractBgmCover(
          Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]),
        ),
        isNull,
      );
      expect(
        extractBgmCover(
          Uint8List.fromList([...'ID3'.codeUnits, 3, 0, 0, 0, 0, 0, 5, 1, 2]),
        ),
        isNull,
      );
    });
  });

  group('importFiles / タグ', () {
    late _FakeStorage storage;
    late CallBgm bgm;
    setUp(() {
      storage = _FakeStorage();
      bgm = CallBgm(
        storage: storage,
        micTrack: () => null,
        replaceOutgoingAudio: (_) async {},
        onPlayingChanged: (_) {},
      );
    });

    BgmImportFile file(String name, String? folder, [int size = 5]) =>
        BgmImportFile(
          name: name,
          folderPath: folder == null ? const [] : folder.split('/'),
          readBytes: () async => Uint8List(size),
        );

    test('ディレクトリから選ぶと、ディレクトリ名のアルバムに入る。同名のアルバムは再利用する', () async {
      final failed = await bgm.importFiles([
        file('02 b.mp3', 'ライブ'),
        file('01 a.mp3', 'ライブ'),
        file('x.mp3', '旅'),
      ]);
      expect(failed, 0);
      expect({for (final a in bgm.albums) a.name}, {'ライブ', '旅'});
      final live = bgm.albums.firstWhere((a) => a.name == 'ライブ');
      // ファイル名の順に入る（追加順＝並び順）。
      expect([for (final t in bgm.tracksOf(live.id)) t.name], ['01 a', '02 b']);

      // もう一度同じディレクトリを選んでも、アルバムも曲も増えない（同名・同サイズは飛ばす）。
      await bgm.importFiles([file('01 a.mp3', 'ライブ'), file('03 c.mp3', 'ライブ')]);
      expect(bgm.albums.length, 2);
      expect(bgm.tracksOf(live.id).length, 3);
    });

    test('個別に選んだ曲は、アルバム指定が無ければアルバムなし。指定があればそこへ', () async {
      await bgm.addAlbum('A');
      final id = bgm.albums.single.id;
      await bgm.importFiles([file('one.mp3', null)]);
      await bgm.importFiles([file('two.mp3', null)], intoAlbumId: id);
      expect(bgm.unclassifiedCount, 1);
      expect(bgm.tracksOf(id).single.name, 'two');
    });

    test('読めない曲は数えて、残りは取り込む', () async {
      final failed = await bgm.importFiles([
        BgmImportFile(
          name: 'bad.mp3',
          readBytes: () async => throw StateError('x'),
        ),
        file('ok.mp3', null),
      ]);
      expect(failed, 1);
      expect(bgm.tracks.single.name, 'ok');
      expect(bgm.importProgress.value, isNull);
    });

    test('アーティスト別（不明は最後）', () async {
      await storage.add(
        name: 'a',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
        artist: 'Zed',
      );
      await storage.add(
        name: 'b',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
        artist: 'Abe',
      );
      await storage.add(name: 'c', mimeType: 'audio/mpeg', bytes: Uint8List(1));
      await bgm.loadTracks();
      final groups = bgm.tracksByArtist();
      expect([for (final g in groups) g.artist], ['Abe', 'Zed', null]);
    });
  });

  group('extractBgmMeta', () {
    Uint8List be32(int n) =>
        Uint8List.fromList([n >> 24, n >> 16 & 255, n >> 8 & 255, n & 255]);
    Uint8List syncsafe(int n) => Uint8List.fromList([
      n >> 21 & 127,
      n >> 14 & 127,
      n >> 7 & 127,
      n & 127,
    ]);

    test('mp3（ID3v2.3、UTF-16とLatin-1）', () {
      List<int> frame(String id, List<int> body) => [
        ...id.codeUnits,
        ...be32(body.length),
        0,
        0,
        ...body,
      ];
      // UTF-16LE（BOM付き）の「雨」
      final title = frame('TIT2', [1, 0xFF, 0xFE, 0xE8, 0x96]);
      final artist = frame('TPE1', [0, ...'TOMOO'.codeUnits]);
      final album = frame('TALB', [0, ...'TOPAZ'.codeUnits]);
      final track = frame('TRCK', [0, ...'3/12'.codeUnits]);
      final frames = [...title, ...artist, ...album, ...track];
      final data = Uint8List.fromList([
        ...'ID3'.codeUnits,
        3,
        0,
        0,
        ...syncsafe(frames.length),
        ...frames,
        ...List.filled(10, 0),
      ]);
      final meta = extractBgmMeta(data);
      expect(meta.title, '雨');
      expect(meta.artist, 'TOMOO');
      expect(meta.album, 'TOPAZ');
      expect(meta.trackNo, 3);
    });

    test('FLAC（Vorbisコメント、UTF-8）', () {
      Uint8List le32(int n) => Uint8List.fromList([
        n & 255,
        n >> 8 & 255,
        n >> 16 & 255,
        n >> 24 & 255,
      ]);
      List<int> comment(String text) {
        final bytes = utf8Encode(text);
        return [...le32(bytes.length), ...bytes];
      }

      final body = <int>[
        ...le32(0), // ベンダー
        ...le32(3),
        ...comment('TITLE=花火'),
        ...comment('artist=TOMOO'),
        ...comment('TRACKNUMBER=7'),
      ];
      final data = Uint8List.fromList([
        ...'fLaC'.codeUnits,
        0x80 | 4,
        body.length >> 16 & 255,
        body.length >> 8 & 255,
        body.length & 255,
        ...body,
      ]);
      final meta = extractBgmMeta(data);
      expect(meta.title, '花火');
      expect(meta.artist, 'TOMOO');
      expect(meta.trackNo, 7);
    });

    test('タグが無い・壊れている時は、空（例外にしない）', () {
      expect(extractBgmMeta(Uint8List(0)).title, isNull);
      expect(extractBgmMeta(Uint8List.fromList([1, 2, 3])).artist, isNull);
    });
  });

  group('ディスク・アルバムの決め方', () {
    test('parseDiscFromDirName', () {
      expect(parseDiscFromDirName('Disc 2'), 2);
      expect(parseDiscFromDirName('disc2'), 2);
      expect(parseDiscFromDirName('CD1'), 1);
      expect(parseDiscFromDirName('cd 3 - bonus'), 3);
      expect(parseDiscFromDirName('ディスク2'), 2);
      expect(parseDiscFromDirName('Discography'), isNull);
      expect(parseDiscFromDirName('CDs'), isNull);
      expect(parseDiscFromDirName('ALBUM'), isNull);
      expect(parseDiscFromDirName('Disc 0'), isNull);
    });

    test('albumNameFromPath: ディスクの階層は飛ばして、一番近いディレクトリ名', () {
      expect(albumNameFromPath(['Music', 'ALBUM', 'CD1']), 'ALBUM');
      expect(albumNameFromPath(['ALBUM']), 'ALBUM');
      expect(albumNameFromPath(['Disc 1']), isNull);
      expect(albumNameFromPath(const []), isNull);
      expect(discFromPath(['ALBUM', 'Disc 2']), 2);
      expect(discFromPath(['ALBUM']), isNull);
    });

    Uint8List syncsafe(int n) => Uint8List.fromList([
      n >> 21 & 127,
      n >> 14 & 127,
      n >> 7 & 127,
      n & 127,
    ]);
    Uint8List be32(int n) =>
        Uint8List.fromList([n >> 24, n >> 16 & 255, n >> 8 & 255, n & 255]);

    Uint8List mp3({
      String? title,
      String? album,
      String? track,
      String? disc,
      int pad = 0,
    }) {
      List<int> frame(String id, String text) {
        final body = [0, ...text.codeUnits];
        return [...id.codeUnits, ...be32(body.length), 0, 0, ...body];
      }

      final frames = [
        if (title != null) ...frame('TIT2', title),
        if (album != null) ...frame('TALB', album),
        if (track != null) ...frame('TRCK', track),
        if (disc != null) ...frame('TPOS', disc),
      ];
      return Uint8List.fromList([
        ...'ID3'.codeUnits,
        3,
        0,
        0,
        ...syncsafe(frames.length),
        ...frames,
        ...List.filled(10 + pad, 0),
      ]);
    }

    late _FakeStorage storage;
    late CallBgm bgm;
    setUp(() {
      storage = _FakeStorage();
      bgm = CallBgm(
        storage: storage,
        micTrack: () => null,
        replaceOutgoingAudio: (_) async {},
        onPlayingChanged: (_) {},
      );
    });

    BgmImportFile f(String name, List<String> path, Uint8List bytes) =>
        BgmImportFile(
          name: name,
          folderPath: path,
          readBytes: () async => bytes,
        );

    test('タグのアルバム名が同じなら、サブディレクトリが違っても1つのアルバム（Disc 1 / Disc 2）', () async {
      await bgm.importFiles([
        f('a.mp3', [
          'X',
          'CD1',
        ], mp3(title: 'one', album: 'THE ALBUM', track: '1/2', disc: '1/2')),
        f('b.mp3', [
          'X',
          'CD1',
        ], mp3(title: 'two', album: 'THE ALBUM', track: '2/2', disc: '1/2')),
        f('c.mp3', [
          'X',
          'CD2',
        ], mp3(title: 'three', album: 'the album ', track: '1/1', disc: '2/2')),
      ]);
      expect(bgm.albums.length, 1);
      final id = bgm.albums.single.id;
      final tracks = bgm.tracksOf(id);
      expect([for (final t in tracks) t.name], ['one', 'two', 'three']);
      expect([for (final t in tracks) t.discNo], [1, 1, 2]);
      expect(bgm.albumHasMultipleDiscs(id), isTrue);
    });

    test('タグが無ければ、ディスクの階層を除いたディレクトリ名のアルバム。CD1/CD2がDisc 1/2に', () async {
      await bgm.importFiles([
        f('01 b.mp3', ['ALBUM', 'CD1'], mp3()),
        f('02 a.mp3', ['ALBUM', 'CD1'], mp3(pad: 1)),
        f('01 c.mp3', ['ALBUM', 'CD2'], mp3(pad: 2)),
      ]);
      expect(bgm.albums.map((a) => a.name), ['ALBUM']);
      final tracks = bgm.tracksOf(bgm.albums.single.id);
      expect([for (final t in tracks) t.discNo], [1, 1, 2]);
      expect([for (final t in tracks) t.name], ['01 b', '02 a', '01 c']);
    });

    test('ディスクが1つだけのアルバムは、複数ディスクの扱いにならない', () async {
      await bgm.importFiles([
        f('a.mp3', ['ALBUM'], mp3(title: 'one', album: 'S', track: '1')),
        f('b.mp3', ['ALBUM'], mp3(title: 'two', album: 'S', track: '2')),
      ]);
      expect(bgm.albumHasMultipleDiscs(bgm.albums.single.id), isFalse);
    });

    test('トラック番号の順に並ぶ（ファイル名の順ではなく）', () async {
      await bgm.importFiles([
        f('a.mp3', ['A'], mp3(title: 'late', album: 'S', track: '3')),
        f('b.mp3', ['A'], mp3(title: 'early', album: 'S', track: '1')),
        f('c.mp3', ['A'], mp3(title: 'mid', album: 'S', track: '2')),
      ]);
      expect(
        [for (final t in bgm.tracksOf(bgm.albums.single.id)) t.name],
        ['early', 'mid', 'late'],
      );
    });

    test('取り込み直すと、既にある曲の分類だけが直る（増えない）', () async {
      // 先に、ディレクトリ名のアルバムへ入れてしまった状態（タグは読まれていない）。
      final old = await storage.add(
        name: 'one',
        mimeType: 'audio/mpeg',
        bytes: Uint8List(1),
      );
      await storage.setTrackAlbum(old.id, (await storage.addAlbum('CD1')).id);
      final bytes = mp3(
        title: 'one',
        album: 'THE ALBUM',
        track: '1',
        disc: '1/2',
      );
      // サイズを合わせる（同じ曲名・同じ大きさ）。
      storage.tracks[old.id] = BgmTrack(
        id: old.id,
        name: 'one',
        mimeType: 'audio/mpeg',
        size: bytes.length,
        albumId: storage.tracks[old.id]!.albumId,
      );
      await bgm.loadTracks();
      await bgm.importFiles([
        f('a.mp3', ['X', 'CD1'], bytes),
      ]);
      expect(bgm.tracks.length, 1);
      final track = bgm.tracks.single;
      final album = bgm.albums.firstWhere((a) => a.id == track.albumId);
      expect(album.name, 'THE ALBUM');
      expect(track.discNo, 1);
    });
  });

  test('extractBgmMeta: ディスク番号（ID3のTPOS・FLACのDISCNUMBER・m4aのdisk）', () {
    Uint8List be32(int n) =>
        Uint8List.fromList([n >> 24, n >> 16 & 255, n >> 8 & 255, n & 255]);
    Uint8List le32(int n) => Uint8List.fromList([
      n & 255,
      n >> 8 & 255,
      n >> 16 & 255,
      n >> 24 & 255,
    ]);
    // FLAC
    final comment = utf8.encode('DISCNUMBER=2');
    final body = <int>[
      ...le32(0),
      ...le32(1),
      ...le32(comment.length),
      ...comment,
    ];
    final flac = Uint8List.fromList([
      ...'fLaC'.codeUnits,
      0x80 | 4,
      body.length >> 16 & 255,
      body.length >> 8 & 255,
      body.length & 255,
      ...body,
    ]);
    expect(extractBgmMeta(flac).discNo, 2);

    // m4a: disk = 予約2バイト + 番号2バイト + 総数2バイト
    Uint8List box(String type, List<int> b) =>
        Uint8List.fromList([...be32(8 + b.length), ...type.codeUnits, ...b]);
    final data = box('data', [...be32(0), ...be32(0), 0, 0, 0, 3, 0, 5, 0, 0]);
    final disk = box('disk', data);
    final ilst = box('ilst', disk);
    final meta = box('meta', [0, 0, 0, 0, ...ilst]);
    final udta = box('udta', meta);
    final moov = box('moov', udta);
    final ftyp = box('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0]);
    expect(extractBgmMeta(Uint8List.fromList([...ftyp, ...moov])).discNo, 3);
  });

  group('CallBgm（複数選択の操作）', () {
    late _FakeStorage storage;
    late CallBgm bgm;
    setUp(() {
      storage = _FakeStorage();
      bgm = CallBgm(
        storage: storage,
        micTrack: () => null,
        replaceOutgoingAudio: (_) async {},
        onPlayingChanged: (_) {},
      );
    });

    Future<void> seed() async {
      await bgm.addAlbum('A');
      for (final n in ['one', 'two', 'three']) {
        await bgm.addTrack(
          name: n,
          mimeType: 'audio/mpeg',
          bytes: Uint8List(n.length),
        );
      }
    }

    test('moveTracks: 選んだ曲だけをまとめて移す（nullでアルバムなし）', () async {
      await seed();
      final id = bgm.albums.single.id;
      final picked = bgm.tracks.where((t) => t.name != 'three').toList();
      await bgm.moveTracks(picked, id);
      expect({for (final t in bgm.tracksOf(id)) t.name}, {'one', 'two'});
      expect(bgm.unclassifiedCount, 1);
      await bgm.moveTracks(bgm.tracksOf(id), null);
      expect(bgm.unclassifiedCount, 3);
    });

    test('removeTracks: 選んだ曲だけを消す', () async {
      await seed();
      final picked = bgm.tracks.where((t) => t.name != 'two').toList();
      await bgm.removeTracks(picked);
      expect([for (final t in bgm.tracks) t.name], ['two']);
    });

    test('お気に入り: 付け外しと、お気に入りの中での次の曲', () async {
      await seed();
      final byName = {for (final t in bgm.tracks) t.name: t};
      await bgm.toggleFavorite(byName['one']!);
      await bgm.setFavorites([byName['three']!], true);
      expect([for (final t in bgm.favorites) t.name], ['one', 'three']);
      expect(bgm.isFavorite(byName['one']!), isTrue);
      await bgm.toggleFavorite(byName['one']!);
      expect(bgm.isFavorite(byName['one']!), isFalse);
      expect([for (final t in bgm.favorites) t.name], ['three']);
    });

    test('曲を全て消すと、空になったアルバムも消える', () async {
      await seed();
      final id = bgm.albums.single.id;
      await bgm.moveTracks(bgm.tracks.take(2).toList(), id);
      await bgm.removeTrack(bgm.tracksOf(id).first);
      expect(bgm.albums, hasLength(1));
      await bgm.removeTracks(bgm.tracksOf(id));
      expect(bgm.albums, isEmpty);
      expect(bgm.tracks, hasLength(1));
    });
  });
  _nowPlayingTests();
}

void _nowPlayingTests() {
  test('BgmNowPlaying: JSONで往復できる（壊れた文字列はnull）', () {
    final np = BgmNowPlaying(
      title: 'song',
      paused: true,
      thumb: Uint8List.fromList([1, 2, 3]),
    );
    final back = BgmNowPlaying.decode(np.encode())!;
    expect(back.title, 'song');
    expect(back.paused, isTrue);
    expect(back.thumb, [1, 2, 3]);
    expect(BgmNowPlaying.decode('not json'), isNull);
  });
}

List<int> utf8Encode(String s) => utf8.encode(s);
