import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 取得した意匠の素材（pack.jsonと背景画像）の、端末への置き場。
/// キーは意匠の識別子と版。版が変われば別のものとして取り直す。
abstract class ThemePackFileCache {
  /// 置いてある最も新しい版。無ければnull。
  Future<int?> latestVersion(String packId);

  /// 置いてある素材（ファイル名→中身）。完全に置けていなければnull。
  Future<Map<String, Uint8List>?> read(String packId, int version);

  /// 素材を置く。同じ意匠の古い版は消す。
  Future<void> write(String packId, int version, Map<String, Uint8List> files);
}

/// 保存先を持たない環境（Web）用。起動中だけ保つ。
class MemoryThemePackCache implements ThemePackFileCache {
  MemoryThemePackCache();

  static final MemoryThemePackCache shared = MemoryThemePackCache();

  final Map<String, (int, Map<String, Uint8List>)> _entries = {};

  @override
  Future<int?> latestVersion(String packId) async => _entries[packId]?.$1;

  @override
  Future<Map<String, Uint8List>?> read(String packId, int version) async {
    final e = _entries[packId];
    return e != null && e.$1 == version ? e.$2 : null;
  }

  @override
  Future<void> write(
    String packId,
    int version,
    Map<String, Uint8List> files,
  ) async {
    _entries[packId] = (version, Map.of(files));
  }
}

/// アプリの保存領域に、意匠ごと・版ごとのフォルダで置く。
/// キャッシュ領域はOSに消されることが有る為、サポート領域を使う。
class FileThemePackCache implements ThemePackFileCache {
  FileThemePackCache({Future<Directory> Function()? root})
    : _root = root ?? _defaultRoot;

  final Future<Directory> Function() _root;
  static const _marker = '.complete';

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/theme_packs');
  }

  Future<Directory> _packDir(String packId) async =>
      Directory('${(await _root()).path}/$packId');

  @override
  Future<int?> latestVersion(String packId) async {
    try {
      final dir = await _packDir(packId);
      if (!await dir.exists()) return null;
      int? best;
      await for (final e in dir.list()) {
        final v = int.tryParse(
          e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        );
        if (v == null) continue;
        if (!await File('${e.path}/$_marker').exists()) continue;
        if (best == null || v > best) best = v;
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, Uint8List>?> read(String packId, int version) async {
    try {
      final dir = Directory('${(await _packDir(packId)).path}/$version');
      if (!await File('${dir.path}/$_marker').exists()) return null;
      final out = <String, Uint8List>{};
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (name == _marker) continue;
        out[name] = await e.readAsBytes();
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    String packId,
    int version,
    Map<String, Uint8List> files,
  ) async {
    try {
      final packDir = await _packDir(packId);
      final dir = Directory('${packDir.path}/$version');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      for (final e in files.entries) {
        await File('${dir.path}/${e.key}').writeAsBytes(e.value, flush: true);
      }
      // 全て書けてから印を付ける。途中で止まった版は読まない。
      await File('${dir.path}/$_marker').writeAsBytes(const [], flush: true);
      await for (final e in packDir.list()) {
        if (e.path != dir.path) await e.delete(recursive: true);
      }
    } catch (_) {
      // 置けなくても、今回は使える。次回また取り直す。
    }
  }
}

ThemePackFileCache createThemePackFileCache() =>
    kIsWeb ? MemoryThemePackCache.shared : _sharedFile;

final FileThemePackCache _sharedFile = FileThemePackCache();
