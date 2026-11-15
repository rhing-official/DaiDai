import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'bgm_cover.dart';
import 'bgm_import_source.dart';
import 'bgm_mixer.dart';
import 'bgm_now_playing.dart';
import 'bgm_queue.dart';
import 'bgm_track.dart';

/// 通話中のBGMの再生状態と操作（2026-11-03）。通話コントローラー（一対・広場）が1つずつ持つ。
/// 再生中だけ、マイクと曲を混ぜたトラックを送信に使い、止めると元のマイクのトラックへ戻す。
/// 曲は端末内（[BgmStorage]）にあり、サーバーには上げない。
/// 音量のスライダーが最大（100%）の時の、実際の音の大きさ（0〜1）。最大を下げて、同じ長さの
/// スライダーでより細かく調整できるようにする（2026-11-15）。
const kBgmMaxGain = 0.5;

class CallBgm extends ChangeNotifier {
  CallBgm({
    required this.storage,
    required this.micTrack,
    required this.replaceOutgoingAudio,
    required this.onPlayingChanged,
    BgmMixer? mixer,
  }) : _mixer = mixer ?? BgmMixer();

  final BgmStorage storage;

  /// 元のマイクのトラック（無ければnull）。
  final MediaStreamTrack? Function() micTrack;

  /// 送信中の音声トラックを、全ての相手に対して差し替える。
  final Future<void> Function(MediaStreamTrack track) replaceOutgoingAudio;

  /// 自分の再生が始まった／一時停止・再開した／止まった（null）時に、相手へ知らせる。
  final void Function(BgmNowPlaying? nowPlaying) onPlayingChanged;

  final BgmMixer _mixer;

  static bool get isSupported => BgmMixer.isSupported;

  List<BgmTrack> _tracks = const [];
  List<BgmTrack> get tracks => _tracks;

  BgmTrack? _current;

  /// 今流している曲（流していなければnull）。
  BgmTrack? get current => _current;
  bool get playing => _current != null;

  String? _thumbTrackId;
  Uint8List? _thumb;

  /// 相手へ知らせる、今の再生の表示用の情報（流していなければnull）。
  BgmNowPlaying? get nowPlaying {
    final track = _current;
    if (track == null) return null;
    return BgmNowPlaying(
      title: track.name,
      paused: _paused,
      thumb: _thumbTrackId == track.id ? _thumb : null,
    );
  }

  /// [track]の小さなジャケットを用意する（相手へ送る用。同じ曲は作り直さない）。
  Future<void> _prepareThumb(BgmTrack track) async {
    if (_thumbTrackId == track.id) return;
    _thumbTrackId = track.id;
    _thumb = null;
    final cover = await coverOf(track);
    if (cover == null) return;
    final small = await shrinkBgmCover(cover);
    if (_thumbTrackId == track.id) _thumb = small;
  }

  double _volume = 0.5;
  double get volume => _volume;

  MediaStreamTrack? _mixed;

  /// 混合中の送信トラック（流していなければnull）。通話の途中で相手が増えた時、
  /// その相手へはマイクの代わりにこれを送る。
  MediaStreamTrack? get mixedTrack => _mixed;

  bool _disposed = false;

  /// 一時停止中か（曲は残り、続きから再開できる）。
  bool _paused = false;
  bool get paused => _paused;

  /// 再生位置と曲の長さ。シークバーだけが描き直されるよう、[ChangeNotifier]とは別に持つ。
  final ValueNotifier<BgmProgress> progress = ValueNotifier(
    const BgmProgress(Duration.zero, null),
  );
  Timer? _progressTimer;

  void _startProgress() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateProgress(),
    );
    _updateProgress();
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    progress.value = const BgmProgress(Duration.zero, null);
  }

  void _updateProgress() {
    if (_disposed) return;
    progress.value = BgmProgress(_mixer.position, _mixer.duration);
  }

  /// 再生位置を動かす。
  void seek(Duration to) {
    _mixer.seek(to);
    _updateProgress();
  }

  /// 一時停止／再開。
  Future<void> togglePause() async {
    if (_current == null) return;
    if (_paused) {
      _paused = false;
      notifyListeners();
      onPlayingChanged(nowPlaying);
      try {
        await _mixer.resume();
      } catch (_) {}
    } else {
      _paused = true;
      _mixer.pause();
      notifyListeners();
      onPlayingChanged(nowPlaying);
    }
  }

  /// 「次へ」。今の再生の範囲（アルバム）の隣の曲へ。
  Future<void> playNext() async {
    final current = _current;
    if (current == null) return;
    final next = adjacentBgmTrack(
      queue: _queueTracks(),
      current: current,
      forward: true,
      order: _order,
    );
    if (next != null)
      await play(
        next,
        albumId: _queueAlbumId,
        inAlbum: true,
        favorites: _queueFavorites,
      );
  }

  /// 「前へ」。3秒より進んでいれば、その曲の頭へ。それ以外は一覧の前の曲へ。
  Future<void> playPrevious() async {
    final current = _current;
    if (current == null) return;
    if (_mixer.position > const Duration(seconds: 3)) {
      seek(Duration.zero);
      return;
    }
    final prev = adjacentBgmTrack(
      queue: _queueTracks(),
      current: current,
      forward: false,
      order: _order,
    );
    if (prev != null)
      await play(
        prev,
        albumId: _queueAlbumId,
        inAlbum: true,
        favorites: _queueFavorites,
      );
  }

  final Map<String, Future<Uint8List?>> _covers = {};

  /// 曲のジャケット画像（無ければnull）。同じ曲は1回だけ読む。
  Future<Uint8List?> coverOf(BgmTrack track) {
    if (!track.hasCover) return Future.value(null);
    return _covers[track.id] ??= storage.cover(track.id);
  }

  List<BgmAlbum> _albums = const [];
  List<BgmAlbum> get albums => _albums;

  /// 再生順（順番・シャッフル・1曲リピート）。
  BgmPlayOrder _order = BgmPlayOrder.inOrder;
  BgmPlayOrder get playOrder => _order;

  /// 今の再生の対象（アルバムのid。nullは、すべての曲）。曲が終わったら、この中の次の曲へ。
  String? _queueAlbumId;

  /// 今の再生の対象が、お気に入りの曲か（trueなら[_queueAlbumId]は使わない）。
  bool _queueFavorites = false;

  List<BgmTrack> _queueTracks() =>
      _queueFavorites ? favorites : tracksOf(_queueAlbumId);

  /// お気に入りの曲（一覧と同じ並び）。
  List<BgmTrack> get favorites =>
      sortBgmTracks(_tracks.where((t) => t.favorite));

  /// [track]が今お気に入りか（流している曲の持つ古い値ではなく、最新の一覧で調べる）。
  bool isFavorite(BgmTrack track) =>
      _tracks.any((t) => t.id == track.id && t.favorite);

  Future<void> toggleFavorite(BgmTrack track) async {
    await storage.setFavorite(track.id, !isFavorite(track));
    await loadTracks();
  }

  /// 選んだ曲を、まとめてお気に入りに入れる／外す。
  Future<void> setFavorites(Iterable<BgmTrack> tracks, bool favorite) async {
    for (final t in tracks) {
      await storage.setFavorite(t.id, favorite);
    }
    await loadTracks();
  }

  Future<void> loadTracks() async {
    _tracks = await storage.list();
    _albums = await storage.listAlbums();
    if (!_disposed) notifyListeners();
  }

  /// [albumId]のアルバムの曲を、並び順に。nullなら、すべての曲（追加順）。
  List<BgmTrack> tracksOf(String? albumId) {
    if (albumId == null) return sortBgmTracks(_tracks);
    final list = sortBgmTracks(_tracks.where((t) => t.albumId == albumId));
    // アルバムの中は、ディスク番号の順（同じディスクの中は並び順のまま。安定ソート）。
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final byDisc = (a.$2.discNo ?? 1).compareTo(b.$2.discNo ?? 1);
      return byDisc != 0 ? byDisc : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// どのアルバムにも入っていない曲の数（一覧の表示用）。
  int get unclassifiedCount => _tracks.where((t) => t.albumId == null).length;

  Future<void> addTrack({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    String? albumId,
  }) async {
    final meta = extractBgmMeta(bytes);
    final duration = await probeBgmDuration(bytes, mimeType);
    await storage.add(
      name: meta.title ?? name,
      mimeType: mimeType,
      bytes: bytes,
      albumId: albumId,
      cover: extractBgmCover(bytes)?.data,
      artist: meta.artist,
      tagAlbum: meta.album,
      trackNo: meta.trackNo,
      durationMs: duration?.inMilliseconds,
    );
    await loadTracks();
  }

  /// 取り込みの進み具合（取り込み中でなければnull）。
  final ValueNotifier<BgmImportProgress?> importProgress = ValueNotifier(null);

  /// アルバム名の比較用（前後の空白・連続する空白・大文字小文字を無視する）。
  static String _albumKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// ファイル名の先頭の数字（`01 xxx`の1）。無ければnull。
  static int? _leadingNumber(String name) {
    final m = RegExp(r'^\s*(\d{1,3})').firstMatch(name);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// ファイルをまとめて取り込む。
  /// - アルバムは、タグのアルバム名（同じなら、サブディレクトリが違っても1つのアルバム）。タグが
  ///   無い曲は、パスの中でディスクを表さない一番近いディレクトリ名のアルバム。どちらも無い曲
  ///   （ファイルを個別に選んだ場合）はアルバムなし。[intoAlbumId]があれば、全てそのアルバムへ。
  /// - ディスク番号は、タグ、無ければ`Disc 2`・`CD2`のようなディレクトリ名から。
  /// - 同じ曲名・同じ大きさの曲が既にあれば、追加せず、その曲の分類（アルバム・ディスク・タグ）
  ///   だけを新しい値に直す。
  /// - 取り込んだアルバムの曲は、（ディスク→トラック番号→ファイル名）の順に並べ直す。
  /// 読めなかった曲の数を返す。
  Future<int> importFiles(
    List<BgmImportFile> files, {
    String? intoAlbumId,
  }) async {
    final sorted = [...files]..sort((a, b) => a.name.compareTo(b.name));
    var failed = 0;
    final albumByKey = <String, String>{
      for (final a in _albums) _albumKey(a.name): a.id,
    };
    final known = [...await storage.list()];
    final touchedAlbums = <String>{};
    for (var i = 0; i < sorted.length; i++) {
      if (_disposed) return failed;
      importProgress.value = BgmImportProgress(i, sorted.length);
      final file = sorted[i];
      try {
        final bytes = await file.readBytes();
        final meta = extractBgmMeta(bytes);
        final title = meta.title ?? bgmFileTitle(file.name);
        final discNo = meta.discNo ?? discFromPath(file.folderPath);
        var albumId = intoAlbumId;
        if (albumId == null) {
          final albumName = meta.album ?? albumNameFromPath(file.folderPath);
          if (albumName != null && albumName.trim().isNotEmpty) {
            final key = _albumKey(albumName);
            albumId = albumByKey[key];
            if (albumId == null) {
              final album = await storage.addAlbum(albumName.trim());
              albumId = album.id;
              albumByKey[key] = albumId;
            }
          }
        }
        if (albumId != null) touchedAlbums.add(albumId);
        final existing = known
            .where((t) => t.name == title && t.size == bytes.length)
            .firstOrNull;
        if (existing != null) {
          await storage.updateTrackMeta(
            existing.id,
            albumId: albumId,
            artist: meta.artist,
            tagAlbum: meta.album,
            trackNo: meta.trackNo,
            discNo: discNo,
          );
          if (existing.albumId != null) touchedAlbums.add(existing.albumId!);
          continue;
        }
        final mime = bgmMimeForFileName(file.name);
        final duration = await probeBgmDuration(bytes, mime);
        final added = await storage.add(
          name: title,
          mimeType: mime,
          bytes: bytes,
          albumId: albumId,
          cover: extractBgmCover(bytes)?.data,
          artist: meta.artist,
          tagAlbum: meta.album,
          trackNo: meta.trackNo,
          discNo: discNo,
          durationMs: duration?.inMilliseconds,
        );
        known.add(added);
      } catch (_) {
        failed++;
      }
    }
    // 取り込んだアルバムの曲を、（ディスク→トラック番号→曲名）の順に並べ直す。
    final all = await storage.list();
    for (final albumId in touchedAlbums) {
      final inAlbum = all.where((t) => t.albumId == albumId).toList()
        ..sort((a, b) {
          final byDisc = (a.discNo ?? 1).compareTo(b.discNo ?? 1);
          if (byDisc != 0) return byDisc;
          final byNo = (a.trackNo ?? _leadingNumber(a.name) ?? 1 << 20)
              .compareTo(b.trackNo ?? _leadingNumber(b.name) ?? 1 << 20);
          return byNo != 0 ? byNo : a.name.compareTo(b.name);
        });
      await storage.reorder([for (final t in inAlbum) t.id]);
    }
    importProgress.value = null;
    await loadTracks();
    return failed;
  }

  /// アルバムに、ディスクが2つ以上あるか（あれば、「Disc 1」「Disc 2」の見出しで区切って出す）。
  bool albumHasMultipleDiscs(String? albumId) {
    if (albumId == null) return false;
    return {for (final t in tracksOf(albumId)) t.discNo ?? 1}.length >= 2;
  }

  /// アーティスト別（タグのアーティスト。無いものは最後の「不明」）。
  List<({String? artist, List<BgmTrack> tracks})> tracksByArtist() {
    final map = <String?, List<BgmTrack>>{};
    for (final t in sortBgmTracks(_tracks)) {
      (map[t.artist] ??= []).add(t);
    }
    final named = map.keys.whereType<String>().toList()..sort();
    return [
      for (final a in named) (artist: a, tracks: map[a]!),
      if (map.containsKey(null)) (artist: null, tracks: map[null]!),
    ];
  }

  /// アルバムの表紙に使う曲（ジャケットがある最初の曲。無ければ最初の曲）。
  BgmTrack? coverTrackOfAlbum(String? albumId) {
    final list = tracksOf(albumId);
    return list.where((t) => t.hasCover).firstOrNull ?? list.firstOrNull;
  }

  Future<void> addAlbum(String name) async {
    await storage.addAlbum(name);
    await loadTracks();
  }

  Future<void> renameAlbum(String id, String name) async {
    await storage.renameAlbum(id, name);
    await loadTracks();
  }

  Future<void> removeAlbum(String id) async {
    await storage.removeAlbum(id);
    if (_queueAlbumId == id) _queueAlbumId = null;
    await loadTracks();
  }

  /// 選んだ曲をまとめて別のアルバムへ移す（nullで、アルバムなし）。
  Future<void> moveTracks(Iterable<BgmTrack> tracks, String? albumId) async {
    for (final t in tracks) {
      await storage.setTrackAlbum(t.id, albumId);
    }
    await loadTracks();
  }

  /// 選んだ曲をまとめて消す（流している曲が含まれていれば、先に止める）。
  Future<void> removeTracks(Iterable<BgmTrack> tracks) async {
    final list = tracks.toList();
    if (_current != null && list.any((t) => t.id == _current!.id)) {
      await stop();
    }
    for (final t in list) {
      await storage.remove(t.id);
    }
    await _pruneEmptyAlbums({for (final t in list) t.albumId});
    await loadTracks();
  }

  /// 曲を消した結果、中の曲が無くなったアルバムも消す（空のディレクトリを残さない）。
  Future<void> _pruneEmptyAlbums(Set<String?> albumIds) async {
    final ids = albumIds.whereType<String>().toSet();
    if (ids.isEmpty) return;
    final remaining = {for (final t in await storage.list()) t.albumId};
    for (final id in ids) {
      if (remaining.contains(id)) continue;
      await storage.removeAlbum(id);
      if (_queueAlbumId == id) _queueAlbumId = null;
    }
  }

  Future<void> moveTrack(BgmTrack track, String? albumId) async {
    await storage.setTrackAlbum(track.id, albumId);
    await loadTracks();
  }

  /// アルバム内の曲の並べ替え（[ordered]は新しい並び）。
  Future<void> reorderTracks(List<BgmTrack> ordered) async {
    await storage.reorder([for (final t in ordered) t.id]);
    await loadTracks();
  }

  /// 再生順を、順番→シャッフル→1曲リピート→順番…と切り替える。
  void cyclePlayOrder() {
    _order =
        BgmPlayOrder.values[(_order.index + 1) % BgmPlayOrder.values.length];
    notifyListeners();
  }

  Future<void> removeTrack(BgmTrack track) async {
    if (_current?.id == track.id) await stop();
    await storage.remove(track.id);
    await _pruneEmptyAlbums({track.albumId});
    await loadTracks();
  }

  /// [track]を流し始める（流していれば入れ替える）。ユーザー操作の中で呼ぶこと
  /// （ブラウザが自動再生を制限する為）。
  Future<void> play(
    BgmTrack track, {
    String? albumId,
    bool inAlbum = false,
    bool favorites = false,
  }) async {
    // 一覧のどこから流したかで、次に流す曲の範囲が決まる（アルバムの中から流せば、そのアルバム）。
    if (inAlbum) {
      _queueAlbumId = albumId;
      _queueFavorites = favorites;
    } else if (_current == null) {
      _queueAlbumId = track.albumId;
      _queueFavorites = false;
    }
    final mic = micTrack();
    if (mic == null) return;
    final bytes = await storage.bytes(track.id);
    if (bytes == null || _disposed) return;
    if (_mixed == null) {
      final mixed = _mixer.attach(mic);
      _mixed = mixed;
      await replaceOutgoingAudio(mixed);
    }
    _mixer.volume = _volume * kBgmMaxGain;
    _current = track;
    _paused = false;
    notifyListeners();
    _lazyStoreCover(track, bytes);
    await _prepareThumb(track);
    if (_current?.id == track.id) onPlayingChanged(nowPlaying);
    try {
      await _mixer.play(bytes, track.mimeType, onEnded: _playNext);
      _startProgress();
    } catch (_) {
      // 再生出来ない曲（壊れたファイル等）。止めて元に戻す。
      await stop();
    }
  }

  /// 追加時にジャケットが無かった曲（この機能の前に入れた曲）は、再生する時に読み取って保存する。
  void _lazyStoreCover(BgmTrack track, Uint8List bytes) {
    if (track.hasCover || _coverTried.contains(track.id)) return;
    _coverTried.add(track.id);
    final cover = extractBgmCover(bytes);
    if (cover == null) return;
    unawaited(() async {
      await storage.setCover(track.id, cover.data);
      await loadTracks();
    }());
  }

  final Set<String> _coverTried = {};

  /// 曲が終わったら一覧の次の曲へ（最後の次は先頭。1曲ならその曲を繰り返す）。
  void _playNext() {
    final current = _current;
    if (current == null || _tracks.isEmpty) return;
    final next = nextBgmTrack(
      queue: _queueTracks(),
      current: current,
      order: _order,
    );
    if (next != null) {
      play(
        next,
        albumId: _queueAlbumId,
        inAlbum: true,
        favorites: _queueFavorites,
      );
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _mixer.volume = _volume * kBgmMaxGain;
    notifyListeners();
  }

  /// 流すのを止め、送信を元のマイクのトラックへ戻す。
  Future<void> stop() async {
    if (_current == null && _mixed == null) return;
    _mixer.stop();
    _stopProgress();
    final hadMixed = _mixed != null;
    _mixed = null;
    _current = null;
    _paused = false;
    if (!_disposed) notifyListeners();
    final mic = micTrack();
    if (hadMixed && mic != null) {
      try {
        await replaceOutgoingAudio(mic);
      } catch (_) {
        // 通話が既に切れている等。
      }
    }
    onPlayingChanged(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    progress.dispose();
    importProgress.dispose();
    _mixer.dispose();
    super.dispose();
  }
}

/// 再生位置と曲の長さ（長さが分からない間はnull）。
class BgmProgress {
  const BgmProgress(this.position, this.duration);

  final Duration position;
  final Duration? duration;
}

/// ディレクトリ・ファイルの取り込みの進み具合。
class BgmImportProgress {
  const BgmImportProgress(this.done, this.total);

  final int done;
  final int total;
}

/// 拡張子を除いたファイル名。
String bgmFileTitle(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

/// 拡張子から音声のMIMEタイプを決める（`<audio>`が形式を判別出来るように）。
String bgmMimeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'mp4' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    'webm' => 'audio/webm',
    _ => 'audio/mpeg',
  };
}
