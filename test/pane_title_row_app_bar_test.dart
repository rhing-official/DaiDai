import 'package:daidai/widgets/pane_title_row_app_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('題名に約9文字ぶんの幅が残らない時だけハンバーガーにまとめる', () {
    // ボタン2つ・文字サイズ24: 必要幅は 2*48 + 24*9 + 32 = 344。
    expect(
      paneNeedsMenu(maxWidth: 343, actionCount: 2, titleFontSize: 24),
      isTrue,
    );
    expect(
      paneNeedsMenu(maxWidth: 344, actionCount: 2, titleFontSize: 24),
      isFalse,
    );
  });

  test('ボタンが多い・文字の拡大率が大きいほど、まとめられやすい', () {
    expect(
      paneNeedsMenu(maxWidth: 500, actionCount: 2, titleFontSize: 16),
      isFalse,
    );
    expect(
      paneNeedsMenu(maxWidth: 500, actionCount: 8, titleFontSize: 16),
      isTrue,
    );
    expect(
      paneNeedsMenu(
        maxWidth: 330,
        actionCount: 2,
        titleFontSize: 16,
        textScale: 1.5,
      ),
      isTrue,
    );
  });
}
