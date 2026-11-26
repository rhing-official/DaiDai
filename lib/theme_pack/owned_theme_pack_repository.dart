import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'theme_pack.dart';
import 'theme_pack_cache.dart';
import 'theme_pack_repository.dart';

/// 取得済みの記録。版は取得した時のもので、素材はこの版を読む。
@immutable
class OwnedThemePackRecord {
  const OwnedThemePackRecord({required this.packId, required this.version});
  final String packId;
  final int version;
}

/// 横丁に公開されている意匠の、今の状態。
@immutable
class PublishedThemePack {
  const PublishedThemePack({
    required this.name,
    required this.version,
    required this.status,
  });
  final String name;
  final int version;

  /// `approved`・`withdrawn`・`suspended`。
  final String status;
}

/// 取得済みの意匠の置き場所を隠すインターフェース（自前化の方針、Repositoryパターン）。
abstract class OwnedThemePackSource {
  Future<List<OwnedThemePackRecord>> listOwned();
  Future<PublishedThemePack?> published(String packId);

  /// [path]のファイルを読む。URLでなく、保存先のパスで持つ。
  Future<Uint8List> readFile(String path, int maxBytes);
}

/// 配信が停止された意匠。標準の版画へ戻す。
class ThemePackSuspendedException extends ThemePackException {
  const ThemePackSuspendedException() : super('配信が停止されました');
}

/// 端末に置いた素材が無く、通信もしない状態（起動直後など）。理由は出さない。
class ThemePackNotCachedException extends ThemePackException {
  const ThemePackNotCachedException() : super('');
}

/// 取得済みの意匠の識別子は、`{投稿者}__{pack.jsonのid}`。
bool isOwnedThemePackId(String id) => id.contains('__');

/// 識別子から、pack.jsonのidを取り出す。
String themePackJsonIdOf(String packId) =>
    packId.substring(packId.lastIndexOf('__') + 2);

/// 公開中の版が、取得した時の版より新しいか。更新の案内にだけ使う。
bool themePackHasUpdate({required int owned, required int latest}) =>
    latest > owned;

const _packJsonMaxBytes = 64 * 1024;
const _imageMaxBytes = 2 * 1024 * 1024;
final _safePackId = RegExp(r'^[A-Za-z0-9_\-]{1,200}$');

/// 取得済みの意匠を読む。[source]がnullなら、端末に置いた素材だけを読む（通信しない）。
class OwnedThemePackRepository implements ThemePackRepository {
  OwnedThemePackRepository({this.source, required this.cache});

  final OwnedThemePackSource? source;
  final ThemePackFileCache cache;

  @override
  Future<List<ThemePackSummary>> list() async {
    final s = source;
    if (s == null) return const [];
    final List<OwnedThemePackRecord> records;
    try {
      records = await s.listOwned();
    } catch (_) {
      return const [];
    }
    final out = <ThemePackSummary>[];
    for (final r in records) {
      if (!_safePackId.hasMatch(r.packId)) continue;
      PublishedThemePack? info;
      try {
        info = await s.published(r.packId);
      } catch (_) {
        info = null;
      }
      if (info == null || info.status == 'suspended') continue;
      out.add(
        ThemePackSummary(
          id: r.packId,
          name: info.name,
          author: '',
          owned: true,
          updateAvailable: themePackHasUpdate(
            owned: r.version,
            latest: info.version,
          ),
        ),
      );
    }
    return out;
  }

  @override
  Future<ThemePack> load(String id) async {
    if (!_safePackId.hasMatch(id) || !isOwnedThemePackId(id)) {
      throw const ThemePackException('idが正しくありません');
    }
    final s = source;
    int? version;
    if (s != null) {
      try {
        final owned = (await s.listOwned()).where((r) => r.packId == id);
        if (owned.isEmpty) {
          throw const ThemePackException('取得していない意匠パックです');
        }
        version = owned.first.version;
        final info = await s.published(id);
        if (info?.status == 'suspended') {
          throw const ThemePackSuspendedException();
        }
      } on ThemePackException {
        rethrow;
      } catch (_) {
        // 通信できない時は、端末に置いた素材で続ける。
      }
    }
    version ??= await cache.latestVersion(id);
    if (version == null) {
      throw s == null
          ? const ThemePackNotCachedException()
          : const ThemePackException('通信できず、意匠パックを取得できません');
    }

    var files = await cache.read(id, version);
    if (files == null) {
      if (s == null) throw const ThemePackNotCachedException();
      files = await _download(s, id, version);
    }
    return _build(id, files);
  }

  Future<Map<String, Uint8List>> _download(
    OwnedThemePackSource s,
    String id,
    int version,
  ) async {
    final base = 'themePacks/$id/$version';
    try {
      final json = await s.readFile('$base/pack.json', _packJsonMaxBytes);
      final parsed = ThemePackParser.parse(utf8.decode(json));
      final files = <String, Uint8List>{'pack.json': json};
      final image = parsed.backgroundImageFile;
      if (image != null) {
        files[image] = await s.readFile('$base/$image', _imageMaxBytes);
      }
      await cache.write(id, version, files);
      return files;
    } on ThemePackException {
      rethrow;
    } catch (_) {
      throw const ThemePackException('通信できず、意匠パックを取得できません');
    }
  }

  ThemePack _build(String id, Map<String, Uint8List> files) {
    final json = files['pack.json'];
    if (json == null) throw const ThemePackException('パックが見つかりません');
    final ParsedThemePack parsed;
    try {
      parsed = ThemePackParser.parse(utf8.decode(json));
    } on FormatException {
      throw const ThemePackException('設定ファイルを読めません');
    }
    if (parsed.pack.id != themePackJsonIdOf(id)) {
      throw const ThemePackException('idが意匠パックの識別子と合いません');
    }
    final pack = parsed.pack.withId(id);
    final image = parsed.backgroundImageFile;
    if (image == null) return pack;
    final bytes = files[image];
    if (bytes == null) throw const ThemePackException('背景画像が見つかりません');
    return pack.withBackgroundImage(MemoryImage(bytes));
  }
}
