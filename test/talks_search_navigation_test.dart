import 'package:daidai/utils/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';

// 語らいのアイコン列の検索ボタン（2026-10-12）。スマホ・タブレットは検索画面へ
// 遷移し、コンピューターだけがインライン検索のまま。
void main() {
  test('スマホ・タブレット（モバイル全般）は検索画面へ遷移する', () {
    expect(opensTalksSearchPage(DeviceClass.phone), isTrue);
    expect(opensTalksSearchPage(DeviceClass.tablet), isTrue);
  });

  test('コンピューターは従来どおりインライン検索', () {
    expect(opensTalksSearchPage(DeviceClass.computer), isFalse);
  });
}
