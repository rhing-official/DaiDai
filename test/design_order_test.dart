import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/theme_pack/design_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final block = styleDesignId(AppUiStyle.block);
  final chalk = styleDesignId(AppUiStyle.chalk);
  final glass = styleDesignId(AppUiStyle.glass);
  final kinari = styleDesignId(AppUiStyle.kinari);
  final flat = styleDesignId(AppUiStyle.flat);
  final gekiga = styleDesignId(AppUiStyle.gekiga);

  test('何も無ければ、標準の並び（版画・チョーク・ガラス・生成り・フラット・劇画）', () {
    expect(
      sortDesignIds(selectedId: block, pins: const [], ownedPackIds: const []),
      [block, chalk, glass, kinari, flat, gekiga],
    );
  });

  test('選択中が最上に移る', () {
    expect(
      sortDesignIds(selectedId: flat, pins: const [], ownedPackIds: const []),
      [flat, block, chalk, glass, kinari, gekiga],
    );
  });

  test('選択中 → ピン留め（留めた順） → 購入 → 標準の並び', () {
    final sakura = packDesignId('sakura');
    final yoru = packDesignId('yoru');
    expect(
      sortDesignIds(
        selectedId: glass,
        pins: [gekiga, sakura],
        ownedPackIds: ['yoru', 'sakura'],
      ),
      [glass, gekiga, sakura, yoru, block, chalk, kinari, flat],
    );
  });

  test('選択中がピン留め済みでも、重複せず最上に1つだけ', () {
    expect(
      sortDesignIds(
        selectedId: chalk,
        pins: [chalk, flat],
        ownedPackIds: const [],
      ),
      [chalk, flat, block, glass, kinari, gekiga],
    );
  });

  test('存在しないデザインのピン留めは無視する', () {
    expect(
      sortDesignIds(
        selectedId: block,
        pins: [packDesignId('gone'), 'style:nothing'],
        ownedPackIds: const [],
      ),
      [block, chalk, glass, kinari, flat, gekiga],
    );
  });

  test('購入した意匠が選択中なら、その意匠が最上', () {
    final sakura = packDesignId('sakura');
    expect(
      sortDesignIds(
        selectedId: sakura,
        pins: const [],
        ownedPackIds: ['sakura'],
      ).first,
      sakura,
    );
  });

  test('旧名style:washiは、生成りとして読み替える', () {
    expect(
      sortDesignIds(
        selectedId: 'style:washi',
        pins: const ['style:washi'],
        ownedPackIds: const [],
      ),
      [kinari, block, chalk, glass, flat, gekiga],
    );
  });

  test('旧い保存値washiは生成りを返す', () {
    expect(AppUiStyle.fromName('washi'), AppUiStyle.kinari);
    expect(AppUiStyle.fromName('kinari'), AppUiStyle.kinari);
  });
}
