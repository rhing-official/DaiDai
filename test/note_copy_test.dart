import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/utils/note_copy.dart';
import 'package:flutter_test/flutter_test.dart';

Node _table(List<List<String>> rows) {
  final cells = <Node>[];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      cells.add(tableCellNode(rows[r][c], r, c));
    }
  }
  return Node(
    type: TableBlockKeys.type,
    attributes: {
      TableBlockKeys.colsLen: rows.first.length,
      TableBlockKeys.rowsLen: rows.length,
    },
    children: cells,
  );
}

void main() {
  test('表の中を選択してコピーすると、Markdownの表になる', () {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [
            _table([
              ['ao', 'aa', 'o-aioai'],
              ['321654', '', ''],
            ]),
          ],
        ),
      ),
    );
    state.selection = Selection(
      start: Position(path: [0, 0, 0]),
      end: Position(path: [0, 5, 0]),
    );
    final markdown = selectionToMarkdownIfTable(state);
    // ignore: avoid_print
    print('MD<<<$markdown>>>');
    expect(markdown, isNotNull);
    final lines = markdown!.trimRight().split('\n');
    expect(lines.length, 3);
    expect(lines.first, contains('ao'));
    expect(lines.first, contains('o-aioai'));
    expect(lines[1], contains('-'));
    expect(lines[2], contains('321654'));
  });

  test('表を含まない選択は通常のコピーに任せる（null）', () {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'abc'),
            paragraphNode(text: 'def'),
          ],
        ),
      ),
    );
    state.selection = Selection(
      start: Position(path: [0]),
      end: Position(path: [1], offset: 3),
    );
    expect(selectionToMarkdownIfTable(state), isNull);
  });
}
