import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/sticker_image.dart';

void main() {
  group('isSvgUrl', () {
    test('拡張子が.svgなら真（クエリは無視する）', () {
      expect(isSvgUrl('https://example.com/a/b.svg'), isTrue);
      expect(
        isSvgUrl(
          'https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/'
          'stickerPackAssets%2Fuid%2F123-neko.svg?alt=media&token=abc',
        ),
        isTrue,
      );
    });

    test('大文字の.SVGも真', () {
      expect(isSvgUrl('https://example.com/NEKO.SVG?alt=media'), isTrue);
    });

    test('ラスタ画像・拡張子の途中のsvg・クエリ側のsvgは偽', () {
      expect(isSvgUrl('https://example.com/a.png'), isFalse);
      expect(isSvgUrl('https://example.com/a.svg.png?alt=media'), isFalse);
      expect(isSvgUrl('https://example.com/a.png?name=b.svg'), isFalse);
      expect(isSvgUrl('https://example.com/svg'), isFalse);
    });

    test('解釈できないURLは偽', () {
      expect(isSvgUrl(''), isFalse);
      expect(isSvgUrl('http://['), isFalse);
    });
  });

  // SVGの描画（SvgPictureの選択）は、テストのHTTPが400を返し読み込み失敗が非同期に漏れて
  // 安定しないため、ここでは確かめない（実機確認）。判定は上のisSvgUrlで担保する。
  group('StickerImage', () {
    testWidgets('それ以外はImageで表示する', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StickerImage(
            'https://example.com/a.png',
            cacheWidth: 96,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });
}
