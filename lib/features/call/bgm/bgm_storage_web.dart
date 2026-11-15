import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'bgm_track.dart';

BgmStorage createBgmStorage() => _IndexedDbBgmStorage();

const _dbName = 'daidai_bgm';
const _storeName = 'tracks';
const _albumStoreName = 'albums';

/// `IndexedDB`に曲を保存する。1曲＝1レコード（メタ情報とバイト列）。
class _IndexedDbBgmStorage implements BgmStorage {
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 2);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      // v1（曲だけ）からの更新では、曲は残し、アルバムの置き場だけを足す（2026-11-15）。
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(
          _storeName,
          web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
        );
      }
      if (!db.objectStoreNames.contains(_albumStoreName)) {
        db.createObjectStore(
          _albumStoreName,
          web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
        );
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDBを開けません'));
    }).toJS;
    return completer.future;
  }();

  Future<JSAny?> _request(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => completer.complete(
      request.result,
    )).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDBの操作に失敗しました'));
    }).toJS;
    return completer.future;
  }

  Future<web.IDBObjectStore> _store(
    String mode, [
    String name = _storeName,
  ]) async {
    final db = await _open();
    return db.transaction(name.toJS, mode).objectStore(name);
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0xFFFFFF)}';

  BgmTrack _toTrack(JSObject record) {
    final albumId = record.getProperty<JSAny?>('albumId'.toJS);
    final order = record.getProperty<JSAny?>('order'.toJS);
    String? text(String key) {
      final v = record.getProperty<JSAny?>(key.toJS);
      return v.isA<JSString>() ? (v as JSString).toDart : null;
    }

    int? number(String key) {
      final v = record.getProperty<JSAny?>(key.toJS);
      return v.isA<JSNumber>() ? (v as JSNumber).toDartInt : null;
    }

    return BgmTrack(
      id: (record.getProperty('id'.toJS) as JSString).toDart,
      name: (record.getProperty('name'.toJS) as JSString).toDart,
      mimeType: (record.getProperty('mimeType'.toJS) as JSString).toDart,
      size: (record.getProperty('size'.toJS) as JSNumber).toDartInt,
      albumId: albumId.isA<JSString>() ? (albumId as JSString).toDart : null,
      order: order.isA<JSNumber>() ? (order as JSNumber).toDartInt : 0,
      hasCover: record.getProperty<JSAny?>('cover'.toJS).isA<JSArrayBuffer>(),
      artist: text('artist'),
      tagAlbum: text('tagAlbum'),
      trackNo: number('trackNo'),
      discNo: number('discNo'),
      durationMs: number('durationMs'),
      favorite:
          record.getProperty<JSAny?>('favorite'.toJS).isA<JSBoolean>() &&
          (record.getProperty('favorite'.toJS) as JSBoolean).toDart,
    );
  }

  @override
  Future<List<BgmTrack>> list() async {
    final store = await _store('readonly');
    final result = await _request(store.getAll());
    final records = (result as JSArray<JSObject>).toDart;
    return [for (final r in records) _toTrack(r)];
  }

  @override
  Future<List<BgmAlbum>> listAlbums() async {
    final store = await _store('readonly', _albumStoreName);
    final result = await _request(store.getAll());
    final records = (result as JSArray<JSObject>).toDart;
    return [
      for (final r in records)
        BgmAlbum(
          id: (r.getProperty('id'.toJS) as JSString).toDart,
          name: (r.getProperty('name'.toJS) as JSString).toDart,
        ),
    ];
  }

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
    final id = _newId();
    // 追加した時刻を並び順にして、末尾に付ける。
    final order = DateTime.now().microsecondsSinceEpoch;
    final record = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('name'.toJS, name.toJS)
      ..setProperty('mimeType'.toJS, mimeType.toJS)
      ..setProperty('size'.toJS, bytes.length.toJS)
      ..setProperty('order'.toJS, order.toJS)
      ..setProperty('data'.toJS, bytes.buffer.toJS);
    if (albumId != null) record.setProperty('albumId'.toJS, albumId.toJS);
    if (cover != null) record.setProperty('cover'.toJS, cover.buffer.toJS);
    if (artist != null) record.setProperty('artist'.toJS, artist.toJS);
    if (tagAlbum != null) record.setProperty('tagAlbum'.toJS, tagAlbum.toJS);
    if (trackNo != null) record.setProperty('trackNo'.toJS, trackNo.toJS);
    if (discNo != null) record.setProperty('discNo'.toJS, discNo.toJS);
    if (durationMs != null) {
      record.setProperty('durationMs'.toJS, durationMs.toJS);
    }
    final store = await _store('readwrite');
    await _request(store.put(record));
    return BgmTrack(
      id: id,
      name: name,
      mimeType: mimeType,
      size: bytes.length,
      albumId: albumId,
      order: order,
      hasCover: cover != null,
      artist: artist,
      tagAlbum: tagAlbum,
      trackNo: trackNo,
      discNo: discNo,
      durationMs: durationMs,
    );
  }

  /// 曲のレコードのうち、バイト列以外を書き換える（取得→書き換え→保存）。
  Future<void> _updateTrack(
    String id,
    void Function(JSObject record) edit,
  ) async {
    final db = await _open();
    final store = db
        .transaction(_storeName.toJS, 'readwrite')
        .objectStore(_storeName);
    final result = await _request(store.get(id.toJS));
    if (result == null) return;
    final record = result as JSObject;
    edit(record);
    await _request(store.put(record));
  }

  @override
  Future<BgmAlbum> addAlbum(String name) async {
    final id = _newId();
    final record = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('name'.toJS, name.toJS);
    final store = await _store('readwrite', _albumStoreName);
    await _request(store.put(record));
    return BgmAlbum(id: id, name: name);
  }

  @override
  Future<void> renameAlbum(String id, String name) async {
    final store = await _store('readwrite', _albumStoreName);
    final record = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('name'.toJS, name.toJS);
    await _request(store.put(record));
  }

  @override
  Future<void> removeAlbum(String id) async {
    // 中の曲は残し、アルバムなしに戻す。
    for (final track in await list()) {
      if (track.albumId == id) await setTrackAlbum(track.id, null);
    }
    final store = await _store('readwrite', _albumStoreName);
    await _request(store.delete(id.toJS));
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
  }) => _updateTrack(id, (record) {
    // 渡された項目だけ書き換える（バイト列・ジャケットはそのまま）。
    if (albumId != null) record.setProperty('albumId'.toJS, albumId.toJS);
    if (artist != null) record.setProperty('artist'.toJS, artist.toJS);
    if (tagAlbum != null) record.setProperty('tagAlbum'.toJS, tagAlbum.toJS);
    if (trackNo != null) record.setProperty('trackNo'.toJS, trackNo.toJS);
    if (discNo != null) record.setProperty('discNo'.toJS, discNo.toJS);
    if (order != null) record.setProperty('order'.toJS, order.toJS);
  });

  @override
  Future<void> setFavorite(String trackId, bool favorite) =>
      _updateTrack(trackId, (record) {
        record.setProperty('favorite'.toJS, favorite.toJS);
      });

  @override
  Future<void> setTrackAlbum(String trackId, String? albumId) =>
      _updateTrack(trackId, (record) {
        if (albumId == null) {
          record.setProperty('albumId'.toJS, null);
        } else {
          record.setProperty('albumId'.toJS, albumId.toJS);
        }
      });

  @override
  Future<void> reorder(List<String> orderedTrackIds) async {
    for (var i = 0; i < orderedTrackIds.length; i++) {
      await _updateTrack(
        orderedTrackIds[i],
        (record) => record.setProperty('order'.toJS, i.toJS),
      );
    }
  }

  @override
  Future<Uint8List?> bytes(String id) async {
    final store = await _store('readonly');
    final result = await _request(store.get(id.toJS));
    if (result == null) return null;
    final data = (result as JSObject).getProperty('data'.toJS) as JSArrayBuffer;
    return data.toDart.asUint8List();
  }

  @override
  Future<Uint8List?> cover(String id) async {
    final store = await _store('readonly');
    final result = await _request(store.get(id.toJS));
    if (result == null) return null;
    final data = (result as JSObject).getProperty<JSAny?>('cover'.toJS);
    if (!data.isA<JSArrayBuffer>()) return null;
    return (data as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<void> setCover(String id, Uint8List cover) => _updateTrack(
    id,
    (record) => record.setProperty('cover'.toJS, cover.buffer.toJS),
  );

  @override
  Future<void> remove(String id) async {
    final store = await _store('readwrite');
    await _request(store.delete(id.toJS));
  }
}
