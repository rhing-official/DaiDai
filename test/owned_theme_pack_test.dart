import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/theme_pack_provider.dart';
import 'package:daidai/theme/block/block_tokens.dart';
import 'package:daidai/theme_pack/owned_theme_pack_repository.dart';
import 'package:daidai/theme_pack/theme_pack.dart';
import 'package:daidai/theme_pack/theme_pack_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _packId = 'uid1__moon';

Uint8List _packJson({String id = 'moon', Map<String, Object?>? extra}) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'id': id,
          'name': '月',
          'author': '誰か',
          'brightness': 'both',
          ...?extra,
        }),
      ),
    );

class _FakeSource implements OwnedThemePackSource {
  _FakeSource({
    this.owned = const [OwnedThemePackRecord(packId: _packId, version: 1)],
    this.status = 'approved',
    this.latest = 1,
    this.offline = false,
    Map<String, Uint8List>? files,
  }) : files =
           files ??
           {
             'themePacks/$_packId/1/pack.json': _packJson(),
             'themePacks/$_packId/2/pack.json': _packJson(),
           };

  List<OwnedThemePackRecord> owned;
  String status;
  int latest;
  bool offline;
  final Map<String, Uint8List> files;
  final List<String> reads = [];

  @override
  Future<List<OwnedThemePackRecord>> listOwned() async {
    if (offline) throw StateError('offline');
    return owned;
  }

  @override
  Future<PublishedThemePack?> published(String packId) async {
    if (offline) throw StateError('offline');
    return PublishedThemePack(name: '月', version: latest, status: status);
  }

  @override
  Future<Uint8List> readFile(String path, int maxBytes) async {
    if (offline) throw StateError('offline');
    reads.add(path);
    return files[path] ?? (throw StateError('missing'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  fileCacheTests();

  test('版の更新の判定', () {
    expect(themePackHasUpdate(owned: 1, latest: 2), isTrue);
    expect(themePackHasUpdate(owned: 2, latest: 2), isFalse);
    expect(themePackHasUpdate(owned: 2, latest: 1), isFalse);
  });

  test('識別子の判定と、pack.jsonのidの取り出し', () {
    expect(isOwnedThemePackId('sakura'), isFalse);
    expect(isOwnedThemePackId(_packId), isTrue);
    expect(themePackJsonIdOf(_packId), 'moon');
  });

  group('一覧の組み立て', () {
    test('取得済みだけを並べ、新しい版を印にする', () async {
      final repo = OwnedThemePackRepository(
        source: _FakeSource(latest: 2),
        cache: MemoryThemePackCache(),
      );
      final list = await repo.list();
      expect(list.map((e) => e.id), [_packId]);
      expect(list.single.owned, isTrue);
      expect(list.single.updateAvailable, isTrue);
    });

    test('配信停止の意匠は出さない', () async {
      final repo = OwnedThemePackRepository(
        source: _FakeSource(status: 'suspended'),
        cache: MemoryThemePackCache(),
      );
      expect(await repo.list(), isEmpty);
    });

    test('取り下げ済みは出し続ける', () async {
      final repo = OwnedThemePackRepository(
        source: _FakeSource(status: 'withdrawn'),
        cache: MemoryThemePackCache(),
      );
      expect((await repo.list()).single.id, _packId);
    });

    test('読めない時や未ログインは、空', () async {
      final offline = OwnedThemePackRepository(
        source: _FakeSource(offline: true),
        cache: MemoryThemePackCache(),
      );
      expect(await offline.list(), isEmpty);
      final loggedOut = OwnedThemePackRepository(cache: MemoryThemePackCache());
      expect(await loggedOut.list(), isEmpty);
    });

    test('廃止した同梱の公式パックの選択は、理由を出さずに外して起動する', () async {
      SharedPreferences.setMockInitialValues({
        'themePackId': 'sakura',
        'appUiStyle': AppUiStyle.block.name,
      });
      final state = await loadInitialThemePack(
        repository: OwnedThemePackRepository(cache: MemoryThemePackCache()),
      );
      expect(state.pack, isNull);
      expect(state.fallbackReason, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('themePackId'),
        isNull,
      );
    });
  });

  group('取得済みの読み込み', () {
    test('取得した版の素材を読み、識別子を持つ。pack.jsonのidは識別子の後ろと照合する', () async {
      final cache = MemoryThemePackCache();
      final src = _FakeSource(latest: 2);
      final pack = await OwnedThemePackRepository(
        source: src,
        cache: cache,
      ).load(_packId);
      expect(pack.id, _packId);
      // 新しい版が有っても、取得した版（1）を読む。
      expect(src.reads, ['themePacks/$_packId/1/pack.json']);
      expect(await cache.latestVersion(_packId), 1);
    });

    test('idが識別子と合わなければ読まない', () async {
      final src = _FakeSource(
        files: {'themePacks/$_packId/1/pack.json': _packJson(id: 'other')},
      );
      expect(
        OwnedThemePackRepository(
          source: src,
          cache: MemoryThemePackCache(),
        ).load(_packId),
        throwsA(isA<ThemePackException>()),
      );
    });

    test('配信停止は、専用の例外', () async {
      expect(
        OwnedThemePackRepository(
          source: _FakeSource(status: 'suspended'),
          cache: MemoryThemePackCache(),
        ).load(_packId),
        throwsA(isA<ThemePackSuspendedException>()),
      );
    });

    test('取得していない意匠は読めない', () async {
      expect(
        OwnedThemePackRepository(
          source: _FakeSource(owned: const []),
          cache: MemoryThemePackCache(),
        ).load(_packId),
        throwsA(isA<ThemePackException>()),
      );
    });
  });

  group('オフラインのキャッシュ', () {
    test('一度読めば、通信できなくても使える。通信しない起動でも読める', () async {
      final cache = MemoryThemePackCache();
      final src = _FakeSource();
      await OwnedThemePackRepository(source: src, cache: cache).load(_packId);

      src.offline = true;
      final offline = await OwnedThemePackRepository(
        source: src,
        cache: cache,
      ).load(_packId);
      expect(offline.id, _packId);

      final cacheOnly = await OwnedThemePackRepository(
        cache: cache,
      ).load(_packId);
      expect(cacheOnly.id, _packId);
    });

    test('キャッシュが無く通信もしない時は、理由の無い例外', () async {
      expect(
        OwnedThemePackRepository(cache: MemoryThemePackCache()).load(_packId),
        throwsA(isA<ThemePackNotCachedException>()),
      );
    });

    test('版が変われば取り直す', () async {
      final cache = MemoryThemePackCache();
      final src = _FakeSource();
      await OwnedThemePackRepository(source: src, cache: cache).load(_packId);
      src.owned = const [OwnedThemePackRecord(packId: _packId, version: 2)];
      await OwnedThemePackRepository(source: src, cache: cache).load(_packId);
      expect(src.reads, [
        'themePacks/$_packId/1/pack.json',
        'themePacks/$_packId/2/pack.json',
      ]);
      expect(await cache.latestVersion(_packId), 2);
    });
  });

  group('配信停止で標準の版画へ戻る', () {
    Future<ProviderContainer> setup(_FakeSource src) async {
      SharedPreferences.setMockInitialValues({
        'themePackId': _packId,
        'appUiStyle': AppUiStyle.block.name,
      });
      final cache = MemoryThemePackCache();
      await OwnedThemePackRepository(source: src, cache: cache).load(_packId);
      final initial = await loadInitialThemePack(
        repository: OwnedThemePackRepository(cache: cache),
      );
      expect(initial.pack?.id, _packId);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          initialThemePackProvider.overrideWithValue(initial),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.block),
          themePackRepositoryProvider.overrideWithValue(
            OwnedThemePackRepository(source: src, cache: cache),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('suspendedで標準へ戻り、保存も消える', () async {
      final src = _FakeSource();
      final container = await setup(src);
      src.status = 'suspended';
      await container.read(themePackProvider.notifier).verify();
      final state = container.read(themePackProvider);
      expect(state.pack, isNull);
      expect(state.suspended, isTrue);
      expect(BlockTokens.current, const BlockTokens());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themePackId'), isNull);
    });

    test('withdrawnは何もしない', () async {
      final src = _FakeSource();
      final container = await setup(src);
      src.status = 'withdrawn';
      await container.read(themePackProvider.notifier).verify();
      expect(container.read(themePackProvider).pack?.id, _packId);
      expect(container.read(themePackProvider).suspended, isFalse);
    });

    test('通信できない時は、そのまま使い続ける', () async {
      final src = _FakeSource();
      final container = await setup(src);
      src.offline = true;
      await container.read(themePackProvider.notifier).verify();
      expect(container.read(themePackProvider).pack?.id, _packId);
    });
  });
}

void fileCacheTests() {
  test('ファイルのキャッシュ: 書いた版を読め、新しい版で古い版は消える', () async {
    final tmp = await Directory.systemTemp.createTemp('tp_cache');
    addTearDown(() => tmp.delete(recursive: true));
    final cache = FileThemePackCache(root: () async => tmp);
    expect(await cache.latestVersion(_packId), isNull);
    await cache.write(_packId, 1, {'pack.json': _packJson()});
    expect(await cache.latestVersion(_packId), 1);
    expect((await cache.read(_packId, 1))!.keys, ['pack.json']);
    await cache.write(_packId, 2, {'pack.json': _packJson()});
    expect(await cache.latestVersion(_packId), 2);
    expect(await cache.read(_packId, 1), isNull);
  });
}
