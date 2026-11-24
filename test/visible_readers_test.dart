import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/message.dart';
import 'package:daidai/utils/visible_readers.dart';

void main() {
  const alice = MessageReadReceipt(userId: 'alice');
  const bob = MessageReadReceipt(userId: 'bob');
  const carol = MessageReadReceipt(userId: 'carol');

  test('削除済みと確定した人だけを外し、順序は保つ', () {
    final result = withoutDeletedReaders([
      alice,
      bob,
      carol,
    ], (id) => id == 'bob');
    expect(result.map((r) => r.userId), ['alice', 'carol']);
  });

  test('削除済みが居なければ、そのまま残る（広場を抜けた人も残る）', () {
    final result = withoutDeletedReaders([alice, bob], (_) => false);
    expect(result.map((r) => r.userId), ['alice', 'bob']);
  });

  test('全員が削除済みなら空になる（✓も出ない）', () {
    expect(withoutDeletedReaders([alice, bob], (_) => true), isEmpty);
  });

  test('元のリストは変えない', () {
    final source = [alice, bob];
    withoutDeletedReaders(source, (id) => id == 'alice');
    expect(source.length, 2);
  });
}
