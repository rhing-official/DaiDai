import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/theme_pack/design_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final block = styleDesignId(AppUiStyle.block);
  final chalk = styleDesignId(AppUiStyle.chalk);
  final glass = styleDesignId(AppUiStyle.glass);
  final washi = styleDesignId(AppUiStyle.washi);
  final flat = styleDesignId(AppUiStyle.flat);
  final gekiga = styleDesignId(AppUiStyle.gekiga);

  test('何も無ければ、標準の並び（版画・チョーク・ガラス・和紙・フラット・劇画）', () {
    expect(
      sortDesignIds(selectedId: block, pins: const [], ownedPackIds: const []),
      [block, chalk, glass, washi, flat, gekiga],
    );
  });

  test('選択中が最上に移る', () {
    expect(
      sortDesignIds(selectedId: flat, pins: const [], ownedPackIds: const []),
      [flat, block, chalk, glass, washi, gekiga],
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
      [glass, gekiga, sakura, yoru, block, chalk, washi, flat],
    );
  });

  test('選択中がピン留め済みでも、重複せず最上に1つだけ', () {
    expect(
      sortDesignIds(
        selectedId: chalk,
        pins: [chalk, flat],
        ownedPackIds: const [],
      ),
      [chalk, flat, block, glass, washi, gekiga],
    );
  });

  test('存在しないデザインのピン留めは無視する', () {
    expect(
      sortDesignIds(
        selectedId: block,
        pins: [packDesignId('gone'), 'style:nothing'],
        ownedPackIds: const [],
      ),
      [block, chalk, glass, washi, flat, gekiga],
    );
  });

  test('購入したパックが選択中なら、そのパックが最上', () {
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
}
