import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/features/note/note_table_delete.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 段落・表(2列×2行)・段落の文書。パスは [0]=前の段落、[1]=表、[2]=後の段落、
/// 表のセルの段落は [1,i,0]（iはセルの順）。
EditorState _stateWithTable({bool paragraphs = true}) {
  final table = TableNode.fromList<String>([
    ['a1', 'a2'],
    ['b1', 'b2'],
  ]).node;
  final children = <Node>[
    if (paragraphs) paragraphNode(text: 'before'),
    table,
    if (paragraphs) paragraphNode(text: 'after'),
  ];
  return EditorState(
    document: Document(root: pageNode(children: children)),
  );
}

Node _firstLeaf(Node table) => table.children.first.children.first;
Node _lastLeaf(Node table) => table.children.last.children.last;

String _plain(Node n) => n.delta?.toPlainText() ?? '';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// 3列×3行の表（セルのテキストは "{列}{行}"、例: c0r1 = 0列目1行目）。
EditorState _gridState() {
  final table = TableNode.fromList<String>([
    ['c0r0', 'c0r1', 'c0r2'],
    ['c1r0', 'c1r1', 'c1r2'],
    ['c2r0', 'c2r1', 'c2r2'],
  ]).node;
  return EditorState(
    document: Document(root: pageNode(children: [table])),
  );
}

Node _cell(Node table, int col, int row) => table.children.firstWhere(
  (c) =>
      c.attributes[TableCellBlockKeys.colPosition] == col &&
      c.attributes[TableCellBlockKeys.rowPosition] == row,
);

/// 表全体のセルのテキストを「行ごとのリスト」で返す（行→列の順）。
List<List<String>> _rows(Node table) {
  final rows = table.attributes[TableBlockKeys.rowsLen] as int;
  final cols = table.attributes[TableBlockKeys.colsLen] as int;
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          _plain(_cell(table, c, r).children.first),
      ],
  ];
}

void _select(EditorState s, Node a, Node b) {
  s.selection = Selection(
    start: Position(path: a.children.first.path),
    end: Position(
      path: b.children.first.path,
      offset: b.children.first.delta!.length,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全セルを覆う範囲選択でBackspaceすると表ごと消える', () async {
    final state = _stateWithTable();
    final table = state.document.root.children[1];
    state.selection = Selection(
      start: Position(path: _firstLeaf(table).path),
      end: Position(
        path: _lastLeaf(table).path,
        offset: _lastLeaf(table).delta!.length,
      ),
    );

    final result = deleteFullySelectedTables(state);
    await _settle();

    expect(result, KeyEventResult.handled);
    expect(state.document.root.children.map(_plain), ['before', 'after']);
    expect(
      state.document.root.children.any((n) => n.type == TableBlockKeys.type),
      isFalse,
    );
  });

  test('1つのセル内の一部選択は対象外', () {
    final state = _stateWithTable();
    final table = state.document.root.children[1];
    state.selection = Selection(
      start: Position(path: _firstLeaf(table).path),
      end: Position(path: _firstLeaf(table).path, offset: 1),
    );
    expect(deleteFullySelectedTables(state), KeyEventResult.ignored);
  });

  test('前後の文章から表をまたぐ選択で表と範囲内の文章が消える', () async {
    final state = _stateWithTable();
    state.selection = Selection(
      start: Position(path: [0], offset: 2),
      end: Position(path: [2], offset: 2),
    );

    final result = deleteFullySelectedTables(state);
    await _settle();
    await _settle();

    expect(result, KeyEventResult.handled);
    expect(
      state.document.root.children.any((n) => n.type == TableBlockKeys.type),
      isFalse,
    );
    // 'be' + 'ter'（before の先頭2文字と after の2文字目以降）が結合される。
    expect(state.document.root.children.map(_plain), ['beter']);
  });

  test('表だけの文書で表を消すと空の段落が残る', () async {
    final state = _stateWithTable(paragraphs: false);
    final table = state.document.root.children.first;
    state.selection = Selection(
      start: Position(path: _firstLeaf(table).path),
      end: Position(
        path: _lastLeaf(table).path,
        offset: _lastLeaf(table).delta!.length,
      ),
    );

    expect(deleteFullySelectedTables(state), KeyEventResult.handled);
    await _settle();

    expect(state.document.root.children.length, 1);
    expect(state.document.root.children.first.type, ParagraphBlockKeys.type);
    expect(_plain(state.document.root.children.first), '');
  });

  test('ブロック選択・折りたたみ選択は対象外', () {
    final state = _stateWithTable();
    state.selection = Selection.collapsed(Position(path: [0]));
    expect(deleteFullySelectedTables(state), KeyEventResult.ignored);
  });

  group('行・列の選択でBackspace/Delete', () {
    test('1行全体を選ぶとその行が削除される', () async {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 0, 1), _cell(table, 2, 1));

      expect(deleteFullySelectedTables(state), KeyEventResult.handled);
      await _settle();
      await _settle();

      expect(_rows(table), [
        ['c0r0', 'c1r0', 'c2r0'],
        ['c0r2', 'c1r2', 'c2r2'],
      ]);
      expect(table.attributes[TableBlockKeys.rowsLen], 2);
    });

    test('複数行（先頭の2行）を選ぶとまとめて削除される', () async {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 0, 0), _cell(table, 2, 1));

      expect(deleteFullySelectedTables(state), KeyEventResult.handled);
      await _settle();
      await _settle();
      await _settle();

      expect(_rows(table), [
        ['c0r2', 'c1r2', 'c2r2'],
      ]);
    });

    test('1列全体を選ぶとその列が削除される', () async {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 1, 0), _cell(table, 1, 2));

      expect(deleteFullySelectedTables(state), KeyEventResult.handled);
      await _settle();
      await _settle();

      expect(_rows(table), [
        ['c0r0', 'c2r0'],
        ['c0r1', 'c2r1'],
        ['c0r2', 'c2r2'],
      ]);
      expect(table.attributes[TableBlockKeys.colsLen], 2);
    });

    test('末尾の2列を選ぶとまとめて削除される', () async {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 1, 0), _cell(table, 2, 2));

      expect(deleteFullySelectedTables(state), KeyEventResult.handled);
      await _settle();
      await _settle();
      await _settle();

      expect(_rows(table), [
        ['c0r0'],
        ['c0r1'],
        ['c0r2'],
      ]);
    });

    test('一部のセルだけ（行も列も全体ではない）は対象外', () {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 0, 0), _cell(table, 1, 1));

      expect(deleteFullySelectedTables(state), KeyEventResult.ignored);
      expect(_rows(table).length, 3);
    });

    test('同じセル内の選択は対象外', () {
      final state = _gridState();
      final table = state.document.root.children.first;
      final cell = _cell(table, 0, 0);
      state.selection = Selection(
        start: Position(path: cell.children.first.path),
        end: Position(path: cell.children.first.path, offset: 2),
      );
      expect(deleteFullySelectedTables(state), KeyEventResult.ignored);
    });

    test('全行・全列を選ぶと従来どおり表ごと削除される', () async {
      final state = _gridState();
      final table = state.document.root.children.first;
      _select(state, _cell(table, 0, 0), _cell(table, 2, 2));

      expect(deleteFullySelectedTables(state), KeyEventResult.handled);
      await _settle();

      expect(
        state.document.root.children.any((n) => n.type == TableBlockKeys.type),
        isFalse,
      );
    });
  });
}
