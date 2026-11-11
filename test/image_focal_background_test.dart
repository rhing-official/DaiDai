import 'package:daidai/models/profile_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('背景色は保存・復元でき、無ければ透明（null）のまま', () {
    const focal = ImageFocal(background: 0xFF123456);
    expect(focal.toJson()['bg'], 0xFF123456);
    expect(ImageFocal.fromJson(focal.toJson())!.background, 0xFF123456);
    expect(ImageFocal.center.toJson().containsKey('bg'), isFalse);
    expect(ImageFocal.fromJson({'dx': 0, 'dy': 0})!.background, isNull);
  });

  test('背景色だけを指定した場合は既定ではなく、clearBackgroundで戻る', () {
    const focal = ImageFocal(background: 0xFFFFFFFF);
    expect(focal.isDefault, isFalse);
    expect(focal.copyWith(clearBackground: true).isDefault, isTrue);
    expect(focal.copyWith(dx: 0.5).background, 0xFFFFFFFF);
  });
}
