import 'package:daidai/models/fcm_token_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('止めていない登録は、muted を書かない（古い登録と同じ形のまま）', () {
    const entry = FcmTokenEntry(token: 't', platform: 'web');
    expect(entry.toJson(), {'token': 't', 'platform': 'web'});
  });

  test('止めている登録は muted: true を書き、読み戻せる', () {
    const entry = FcmTokenEntry(token: 't', platform: 'android', muted: true);
    expect(entry.toJson(), {
      'token': 't',
      'platform': 'android',
      'muted': true,
    });
    expect(FcmTokenEntry.fromJson(entry.toJson()).muted, isTrue);
  });

  test('muted が無い古い登録は、止めていない扱い', () {
    final entry = FcmTokenEntry.fromJson({'token': 't', 'platform': 'web'});
    expect(entry.muted, isFalse);
  });
}
