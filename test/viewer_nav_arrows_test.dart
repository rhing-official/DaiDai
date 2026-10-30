import 'package:daidai/widgets/viewer_nav_arrows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('先頭は左を、末尾は右を隠し、1件だけなら両方隠す', () {
    expect(ViewerNavArrows.showsPrevious(0, 5), isFalse);
    expect(ViewerNavArrows.showsNext(0, 5), isTrue);
    expect(ViewerNavArrows.showsPrevious(2, 5), isTrue);
    expect(ViewerNavArrows.showsNext(2, 5), isTrue);
    expect(ViewerNavArrows.showsPrevious(4, 5), isTrue);
    expect(ViewerNavArrows.showsNext(4, 5), isFalse);
    expect(ViewerNavArrows.showsPrevious(0, 1), isFalse);
    expect(ViewerNavArrows.showsNext(0, 1), isFalse);
  });
}
