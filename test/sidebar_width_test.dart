import 'package:daidai/providers/text_size_provider.dart';
import 'package:daidai/utils/sidebar_width.dart';
import 'package:flutter_test/flutter_test.dart';

// 設定・身だしなみ・語らいのサイドバー幅は、フォントサイズ別（2026-11-06）。
void main() {
  test('フォントサイズ別の幅（小230・中270・大310、2026-11-12に広げた）', () {
    expect(sidebarWidthFor(AppTextSize.large), 310);
    expect(sidebarWidthFor(AppTextSize.medium), 270);
    expect(sidebarWidthFor(AppTextSize.small), 230);
  });

  test('小<中<大の順に広がる', () {
    expect(
      sidebarWidthFor(AppTextSize.small) < sidebarWidthFor(AppTextSize.medium),
      isTrue,
    );
    expect(
      sidebarWidthFor(AppTextSize.medium) < sidebarWidthFor(AppTextSize.large),
      isTrue,
    );
  });
}
