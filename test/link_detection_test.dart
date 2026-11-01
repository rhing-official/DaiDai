import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/utils/link_detection.dart';

void main() {
  test('複数のURLを出現順に、重複を除いて返す', () {
    expect(
      urlsIn(
        'a https://a.example/1 b https://b.example/2 c https://a.example/1',
      ),
      ['https://a.example/1', 'https://b.example/2'],
    );
    expect(urlsIn('URLなし'), isEmpty);
  });

  test('上限を超えるURLは捨てる', () {
    final text = [for (var i = 0; i < 9; i++) 'https://x.example/$i'].join(' ');
    expect(urlsIn(text), hasLength(kMaxLinkPreviews));
    expect(urlsIn(text, limit: 2), hasLength(2));
  });
}
