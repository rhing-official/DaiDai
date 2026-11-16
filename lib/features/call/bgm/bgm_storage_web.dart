import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'bgm_track.dart';

BgmStorage createBgmStorage() => _IndexedDbBgmStorage();

const _dbName = 'daidai_bgm';

/// v3以降の保存先。曲のレコードを、一覧に要る小さなメタ情報（[_metaStore]）と、重い音源
/// （[_dataStore]）・ジャケット（[_coverStore]）に分けて持つ（2026-11-16）。以前は1曲＝1レコードに
/// 音源まで入っていた為、一覧を出すだけで全曲（数GB）をメモリに読み込んで、シートを開くのが遅かった。
const _metaStore = 'trackMeta';
const _dataStore = 'trackData';
const _coverStore = 'trackCovers';
const _albumStoreName = 'albums';

/// アーティスト写真（キー`id`＝アーティスト名、`photo`＝画像、v4、2026-11-16）。
const _artistPhotoStore = 'artistPhotos';

/// v1・v2の曲の保存先（音源入り）。起動後に、1曲ずつ新しい保存先へ移して、空にする。
const _legacyStore = 'tracks';

/// 曲のメタ情報として持つ項目（音源・ジャケット以外）。
const _metaKeys = [
  'id',
  'name',
  'mimeType',
  'size',
  'order',
  'albumId',
  'artist',
  'tagAlbum',
  'trackNo',
  'discNo',
  'durationMs',
  'favorite',
];

/// `IndexedDB`に曲を保存する。1曲＝メタ情報・音源・ジャケットの3レコード（同じid）。
class _IndexedDbBgmStorage implements BgmStorage {
  Future<web.IDBDatabase>? _db;
  Future<void>? _ready;

  Future<web.IDBDatabase> _open() => _db ??= () {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 4);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      // 古い版の曲（_legacyStore）は残し、新しい置き場を足すだけにする（中身の移行は、起動後に
      // 1曲ずつ行う。この更新の中で全曲を書き換えると、容量が一時的に倍になり失敗しうる）。
      for (final name in [
        _legacyStore,
        _metaStore,
        _dataStore,
        _coverStore,
        _albumStoreName,
        _artistPhotoStore,
      ]) {
        if (!db.objectStoreNames.contains(name)) {
          db.createObjectStore(
            name,
            web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
          );
        }
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

  /// 開いて、古い版の曲を新しい保存先へ移し終えるまで待つ（1回だけ）。
  Future<void> _prepare() => _ready ??= () async {
    final db = await _open();
    await _migrateLegacy(db);
  }();

  /// 古い版の曲（音源入り）を、1曲ずつ新しい保存先へ移す。1曲ごとに、3つの保存先への書き込みと
  /// 古いレコードの削除を、1つのトランザクションで行う（途中で止まっても、曲は失われない）。
  Future<void> _migrateLegacy(web.IDBDatabase db) async {
    final keysRequest = db
        .transaction(_legacyStore.toJS, 'readonly')
        .objectStore(_legacyStore)
        .getAllKeys();
    final keys = await _request(keysRequest);
    if (keys == null) return;
    for (final key in (keys as JSArray<JSAny?>).toDart) {
      if (!key.isA<JSString>()) continue;
      try {
        await _migrateOne(db, key as JSString);
      } catch (e) {
        // 移せなかった曲は、古い場所に残す（次の起動で、もう一度試す）。
        debugPrint('BGM: 曲の移行に失敗 $e');
      }
    }
  }

  Future<void> _migrateOne(web.IDBDatabase db, JSString id) async {
    final tx = db.transaction(
      [
        _legacyStore.toJS,
        _metaStore.toJS,
        _dataStore.toJS,
        _coverStore.toJS,
      ].toJS,
      'readwrite',
    );
    final legacy = tx.objectStore(_legacyStore);
    final result = await _request(legacy.get(id));
    if (result == null) return;
    final record = result as JSObject;
    final data = record.getProperty<JSAny?>('data'.toJS);
    final cover = record.getProperty<JSAny?>('cover'.toJS);
    final hasCover = cover.isA<JSArrayBuffer>();
    final meta = JSObject();
    for (final key in _metaKeys) {
      final v = record.getProperty<JSAny?>(key.toJS);
      if (v != null) meta.setProperty(key.toJS, v);
    }
    meta.setProperty('hasCover'.toJS, hasCover.toJS);
    if (data != null) {
      tx
          .objectStore(_dataStore)
          .put(
            JSObject()
              ..setProperty('id'.toJS, id)
              ..setProperty('data'.toJS, data),
          );
    }
    if (hasCover) {
      tx
          .objectStore(_coverStore)
          .put(
            JSObject()
              ..setProperty('id'.toJS, id)
              ..setProperty('cover'.toJS, cover),
          );
    }
    tx.objectStore(_metaStore).put(meta);
    legacy.delete(id);
    await _transactionDone(tx);
  }

  Future<void> _transactionDone(web.IDBTransaction tx) {
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
    tx.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDBの書き込みに失敗しました'));
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDBの書き込みが中止されました'));
      }
    }).toJS;
    return completer.future;
  }

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
    String name = _metaStore,
  ]) async {
    await _prepare();
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
      hasCover:
          record.getProperty<JSAny?>('hasCover'.toJS).isA<JSBoolean>() &&
          (record.getProperty('hasCover'.toJS) as JSBoolean).toDart,
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
      ..setProperty('hasCover'.toJS, (cover != null).toJS);
    if (albumId != null) record.setProperty('albumId'.toJS, albumId.toJS);
    if (artist != null) record.setProperty('artist'.toJS, artist.toJS);
    if (tagAlbum != null) record.setProperty('tagAlbum'.toJS, tagAlbum.toJS);
    if (trackNo != null) record.setProperty('trackNo'.toJS, trackNo.toJS);
    if (discNo != null) record.setProperty('discNo'.toJS, discNo.toJS);
    if (durationMs != null) {
      record.setProperty('durationMs'.toJS, durationMs.toJS);
    }
    await _prepare();
    final db = await _open();
    final tx = db.transaction(
      [
        _metaStore.toJS,
        _dataStore.toJS,
        if (cover != null) _coverStore.toJS,
      ].toJS,
      'readwrite',
    );
    tx.objectStore(_metaStore).put(record);
    tx
        .objectStore(_dataStore)
        .put(
          JSObject()
            ..setProperty('id'.toJS, id.toJS)
            ..setProperty('data'.toJS, bytes.buffer.toJS),
        );
    if (cover != null) {
      tx
          .objectStore(_coverStore)
          .put(
            JSObject()
              ..setProperty('id'.toJS, id.toJS)
              ..setProperty('cover'.toJS, cover.buffer.toJS),
          );
    }
    await _transactionDone(tx);
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

  /// 曲のメタ情報のレコードを書き換える（取得→書き換え→保存。音源・ジャケットは別の保存先）。
  Future<void> _updateTrack(
    String id,
    void Function(JSObject record) edit,
  ) async {
    await _prepare();
    final db = await _open();
    final store = db
        .transaction(_metaStore.toJS, 'readwrite')
        .objectStore(_metaStore);
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
    final store = await _store('readonly', _dataStore);
    final result = await _request(store.get(id.toJS));
    if (result == null) return null;
    final data = (result as JSObject).getProperty('data'.toJS) as JSArrayBuffer;
    return data.toDart.asUint8List();
  }

  @override
  Future<Uint8List?> cover(String id) async {
    final store = await _store('readonly', _coverStore);
    final result = await _request(store.get(id.toJS));
    if (result == null) return null;
    final data = (result as JSObject).getProperty<JSAny?>('cover'.toJS);
    if (!data.isA<JSArrayBuffer>()) return null;
    return (data as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<void> setCover(String id, Uint8List cover) async {
    await _prepare();
    final db = await _open();
    final tx = db.transaction(
      [_metaStore.toJS, _coverStore.toJS].toJS,
      'readwrite',
    );
    final metaStore = tx.objectStore(_metaStore);
    final result = await _request(metaStore.get(id.toJS));
    if (result == null) return;
    final record = result as JSObject..setProperty('hasCover'.toJS, true.toJS);
    metaStore.put(record);
    tx
        .objectStore(_coverStore)
        .put(
          JSObject()
            ..setProperty('id'.toJS, id.toJS)
            ..setProperty('cover'.toJS, cover.buffer.toJS),
        );
    await _transactionDone(tx);
  }

  @override
  Future<Map<String, Uint8List>> listArtistPhotos() async {
    final store = await _store('readonly', _artistPhotoStore);
    final result = await _request(store.getAll());
    final out = <String, Uint8List>{};
    if (result == null) return out;
    for (final item in (result as JSArray<JSAny?>).toDart) {
      final record = item as JSObject;
      final name = record.getProperty<JSAny?>('id'.toJS);
      final photo = record.getProperty<JSAny?>('photo'.toJS);
      if (name.isA<JSString>() && photo.isA<JSArrayBuffer>()) {
        out[(name as JSString).toDart] = (photo as JSArrayBuffer).toDart
            .asUint8List();
      }
    }
    return out;
  }

  @override
  Future<void> setArtistPhoto(String artist, Uint8List? photo) async {
    await _prepare();
    final db = await _open();
    final tx = db.transaction(_artistPhotoStore.toJS, 'readwrite');
    final store = tx.objectStore(_artistPhotoStore);
    if (photo == null) {
      store.delete(artist.toJS);
    } else {
      store.put(
        JSObject()
          ..setProperty('id'.toJS, artist.toJS)
          ..setProperty('photo'.toJS, photo.buffer.toJS),
      );
    }
    await _transactionDone(tx);
  }

  @override
  Future<void> remove(String id) async {
    await _prepare();
    final db = await _open();
    final tx = db.transaction(
      [_metaStore.toJS, _dataStore.toJS, _coverStore.toJS].toJS,
      'readwrite',
    );
    tx.objectStore(_metaStore).delete(id.toJS);
    tx.objectStore(_dataStore).delete(id.toJS);
    tx.objectStore(_coverStore).delete(id.toJS);
    await _transactionDone(tx);
  }
}
