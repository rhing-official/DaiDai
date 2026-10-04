import 'package:daidai/features/note/blocks/table_of_contents_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('最小レベルを第0階層とする相対階層になる', () {
    expect(tocIndentLevels([2, 3, 3, 2]), [0, 1, 1, 0]);
    expect(tocIndentLevels([1, 2, 3, 4, 5]), [0, 1, 2, 3, 3]);
    expect(tocIndentLevels([3, 3]), [0, 0]);
    expect(tocIndentLevels(const []), isEmpty);
  });
}
