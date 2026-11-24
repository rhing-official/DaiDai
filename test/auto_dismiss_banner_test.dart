import 'package:daidai/utils/auto_dismiss_banner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('文末の句点・ピリオドを取り除く', () {
    expect(stripBannerTrailingPeriod('追加しました。'), '追加しました');
    expect(stripBannerTrailingPeriod('Saved.'), 'Saved');
    expect(stripBannerTrailingPeriod('完了．'), '完了');
    expect(stripBannerTrailingPeriod('追加しました。\n'), '追加しました');
  });

  test('文の途中の句点と、省略の点は残す', () {
    expect(stripBannerTrailingPeriod('失敗しました。もう一度どうぞ。'), '失敗しました。もう一度どうぞ');
    expect(stripBannerTrailingPeriod('読み込み中...'), '読み込み中...');
    expect(stripBannerTrailingPeriod('読み込み中…'), '読み込み中…');
  });

  test('句点が無ければそのまま', () {
    expect(stripBannerTrailingPeriod('追加しました'), '追加しました');
  });
}
