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

/// `IndexedDB`に曲を保存する。1曲＝1レコード（メタ情報とバイト列）。
class _IndexedDbBgmStorage implements BgmStorage {
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      db.createObjectStore(
        _storeName,
        web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
      );
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

  Future<web.IDBObjectStore> _store(String mode) async {
    final db = await _open();
    return db.transaction(_storeName.toJS, mode).objectStore(_storeName);
  }

  BgmTrack _toTrack(JSObject record) => BgmTrack(
    id: (record.getProperty('id'.toJS) as JSString).toDart,
    name: (record.getProperty('name'.toJS) as JSString).toDart,
    mimeType: (record.getProperty('mimeType'.toJS) as JSString).toDart,
    size: (record.getProperty('size'.toJS) as JSNumber).toDartInt,
  );

  @override
  Future<List<BgmTrack>> list() async {
    final store = await _store('readonly');
    final result = await _request(store.getAll());
    final records = (result as JSArray<JSObject>).toDart;
    return [for (final r in records) _toTrack(r)];
  }

  @override
  Future<BgmTrack> add({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0xFFFFFF)}';
    final record = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('name'.toJS, name.toJS)
      ..setProperty('mimeType'.toJS, mimeType.toJS)
      ..setProperty('size'.toJS, bytes.length.toJS)
      ..setProperty('data'.toJS, bytes.buffer.toJS);
    final store = await _store('readwrite');
    await _request(store.put(record));
    return BgmTrack(id: id, name: name, mimeType: mimeType, size: bytes.length);
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
  Future<void> remove(String id) async {
    final store = await _store('readwrite');
    await _request(store.delete(id.toJS));
  }
}
