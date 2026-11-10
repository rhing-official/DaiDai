import 'package:daidai/widgets/pane_title_row_app_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('題名に約9文字ぶんの幅が残らない時だけ2段にする', () {
    // ボタン2つ・文字サイズ24: 必要幅は 2*48 + 24*9 + 32 = 344。
    expect(
      paneNeedsTitleRow(maxWidth: 343, actionCount: 2, titleFontSize: 24),
      isTrue,
    );
    expect(
      paneNeedsTitleRow(maxWidth: 344, actionCount: 2, titleFontSize: 24),
      isFalse,
    );
  });

  test('ボタンが多い・文字の拡大率が大きいほど、2段になりやすい', () {
    expect(
      paneNeedsTitleRow(maxWidth: 500, actionCount: 2, titleFontSize: 16),
      isFalse,
    );
    expect(
      paneNeedsTitleRow(maxWidth: 500, actionCount: 8, titleFontSize: 16),
      isTrue,
    );
    expect(
      paneNeedsTitleRow(
        maxWidth: 330,
        actionCount: 2,
        titleFontSize: 16,
        textScale: 1.5,
      ),
      isTrue,
    );
  });
}
