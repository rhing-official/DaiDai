import 'package:daidai/providers/last_sticker_tab_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stickerTabKeyは寄合があれば会話/寄合、無ければ会話、どちらも無ければnull', () {
    expect(stickerTabKey(conversationId: 'g1', roomId: 'r1'), 'g1/r1');
    expect(stickerTabKey(conversationId: 'g1'), 'g1');
    expect(stickerTabKey(roomId: 'r1'), isNull);
  });

  test('rememberTabは更新したものを末尾にし、同じキーは上書きする', () {
    var map = rememberTab(const {}, 'a', 'p1');
    map = rememberTab(map, 'b', kStickerTabRecent);
    map = rememberTab(map, 'a', kStickerTabAll);
    expect(map, {'b': kStickerTabRecent, 'a': kStickerTabAll});
    expect(map.keys.last, 'a');
  });

  test('上限を超えたら古いものから落とす', () {
    var map = <String, String>{};
    for (var i = 0; i < kLastStickerTabLimit + 5; i++) {
      map = rememberTab(map, 'k$i', 'p');
    }
    expect(map.length, kLastStickerTabLimit);
    expect(map.containsKey('k0'), isFalse);
    expect(map.containsKey('k${kLastStickerTabLimit + 4}'), isTrue);
  });
}
