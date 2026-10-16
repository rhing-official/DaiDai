import 'package:daidai/widgets/video_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';

// 動画サムネイルの表示位置（基本1秒、短い動画は先頭付近）の回帰テスト。
void main() {
  test('1.5秒以上は1秒の位置', () {
    expect(
      previewPositionFor(const Duration(seconds: 10)),
      const Duration(seconds: 1),
    );
    expect(
      previewPositionFor(const Duration(milliseconds: 1500)),
      const Duration(seconds: 1),
    );
  });

  test('1.5秒未満は0.3秒、それより短ければ半分', () {
    expect(
      previewPositionFor(const Duration(milliseconds: 1000)),
      const Duration(milliseconds: 300),
    );
    expect(
      previewPositionFor(const Duration(milliseconds: 400)),
      const Duration(milliseconds: 200),
    );
  });

  test('長さ不明（0）は先頭', () {
    expect(previewPositionFor(Duration.zero), Duration.zero);
  });
}
