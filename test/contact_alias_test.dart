import 'package:daidai/utils/contact_alias.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveDisplayName', () {
    test('自分が指定した呼び名が最優先', () {
      expect(
        resolveDisplayName(alias: 'たろう', nickname: '相手の呼び名', rhingSeed: 'a'),
        'たろう',
      );
    });

    test('指定が無ければ相手の呼び名', () {
      expect(
        resolveDisplayName(alias: null, nickname: '相手の呼び名', rhingSeed: 'a'),
        '相手の呼び名',
      );
    });

    test('空白だけの指定・呼び名は無いものとして扱い、最後は@Rhing Seed', () {
      expect(
        resolveDisplayName(alias: '  ', nickname: '', rhingSeed: 'abc'),
        '@abc',
      );
    });
  });

  group('aliasOf', () {
    test('指定があれば返し、無い・空なら null', () {
      final aliases = {'u1': 'たろう', 'u2': ' '};
      expect(aliasOf(aliases, 'u1'), 'たろう');
      expect(aliasOf(aliases, 'u2'), isNull);
      expect(aliasOf(aliases, 'u3'), isNull);
      expect(aliasOf(null, 'u1'), isNull);
    });
  });
}
