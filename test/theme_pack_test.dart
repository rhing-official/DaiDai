import 'dart:convert';

import 'package:daidai/theme_pack/theme_pack.dart';
import 'package:daidai/theme_pack/theme_pack_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _json(Map<String, Object?> overrides) => jsonEncode({
  'formatVersion': 1,
  'id': 'test-pack',
  'name': 'テスト',
  'author': '誰か',
  'brightness': 'both',
  ...overrides,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemePackParser', () {
    test('正しい設定ファイルを読める', () {
      final parsed = ThemePackParser.parse(
        _json({
          'shape': {
            'borderWidth': 3,
            'radius': 12,
            'shadowOffset': [5, 6],
          },
          'colors': {
            'light': {'accent': '#112233', 'line': '#445566'},
            'dark': {'background': '#000000'},
          },
          'images': {'background': 'bg.webp'},
        }),
      );
      final pack = parsed.pack;
      expect(pack.id, 'test-pack');
      expect(pack.tokens.borderWidth, 3);
      expect(pack.tokens.radius, 12);
      expect(pack.tokens.shadowOffset, const Offset(5, 6));
      expect(pack.light.accent, const Color(0xFF112233));
      expect(pack.tokens.lightLine, const Color(0xFF445566));
      expect(pack.dark.background, const Color(0xFF000000));
      expect(parsed.backgroundImageFile, 'bg.webp');
    });

    test('範囲外の数値は範囲へ丸める', () {
      final pack = ThemePackParser.parse(
        _json({
          'shape': {
            'borderWidth': 99,
            'radius': -5,
            'shadowOffset': [100, -100],
          },
        }),
      ).pack;
      expect(pack.tokens.borderWidth, ThemePackParser.maxBorderWidth);
      expect(pack.tokens.radius, 0);
      expect(pack.tokens.shadowOffset, const Offset(12, -12));
    });

    test('透明度の付いた色は不透明にし、読めない色は未指定にする', () {
      final pack = ThemePackParser.parse(
        _json({
          'colors': {
            'light': {'accent': '#11223300', 'text': 'あか'},
          },
        }),
      ).pack;
      expect(pack.light.accent, const Color(0xFF112233));
      expect(pack.light.text, isNull);
    });

    test('項目が無くても既定で読める', () {
      final pack = ThemePackParser.parse(_json({})).pack;
      expect(pack.tokens.borderWidth, 2.5);
      expect(pack.tokens.radius, 8);
      expect(pack.light.accent, isNull);
      expect(pack.paletteFor(Brightness.light), isNull);
    });

    test('背景色を指定すれば、面の色の組が出来る', () {
      final pack = ThemePackParser.parse(
        _json({
          'colors': {
            'light': {'background': '#FFFFFF', 'panel': '#EEEEEE'},
          },
        }),
      ).pack;
      final palette = pack.paletteFor(Brightness.light)!;
      expect(palette.background, const Color(0xFFFFFFFF));
      expect(palette.surface, const Color(0xFFEEEEEE));
    });

    test('対応する明るさが片方なら、その明るさに固定する', () {
      expect(
        ThemePackParser.parse(
          _json({'brightness': 'dark'}),
        ).pack.forcedThemeMode,
        ThemeMode.dark,
      );
      expect(
        ThemePackParser.parse(
          _json({'brightness': 'both'}),
        ).pack.forcedThemeMode,
        isNull,
      );
    });

    test('壊れた設定ファイル・新しすぎる版・不正なidは読まない', () {
      expect(
        () => ThemePackParser.parse('{'),
        throwsA(isA<ThemePackException>()),
      );
      expect(
        () => ThemePackParser.parse('[]'),
        throwsA(isA<ThemePackException>()),
      );
      expect(
        () => ThemePackParser.parse(_json({'formatVersion': 99})),
        throwsA(isA<ThemePackException>()),
      );
      expect(
        () => ThemePackParser.parse(_json({'formatVersion': null})),
        throwsA(isA<ThemePackException>()),
      );
      expect(
        () => ThemePackParser.parse(_json({'id': '../x'})),
        throwsA(isA<ThemePackException>()),
      );
      expect(
        () => ThemePackParser.parse(_json({'name': ' '})),
        throwsA(isA<ThemePackException>()),
      );
    });

    test('パックの外を指す画像のパスは読まない', () {
      for (final bad in [
        '../a.png',
        '/etc/passwd',
        'https://x/y.png',
        'a/b.png',
      ]) {
        expect(
          () => ThemePackParser.parse(
            _json({
              'images': {'background': bad},
            }),
          ),
          throwsA(isA<ThemePackException>()),
          reason: bad,
        );
      }
    });
  });

  group('BundledThemePackRepository', () {
    test('同梱の公式パックを全て読める', () async {
      final repo = BundledThemePackRepository();
      final list = await repo.list();
      expect(
        list.map((e) => e.id),
        containsAll(['sakura', 'yoru', 'mizutama']),
      );
      for (final summary in list) {
        final pack = await repo.load(summary.id);
        expect(pack.id, summary.id);
      }
      expect((await repo.load('sakura')).backgroundImage, isNotNull);
    });

    test('無いパックと不正なidは、理由付きで失敗する', () async {
      final repo = BundledThemePackRepository();
      expect(() => repo.load('nothing'), throwsA(isA<ThemePackException>()));
      expect(() => repo.load('../x'), throwsA(isA<ThemePackException>()));
    });
  });
}
