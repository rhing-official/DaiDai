import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ノートの表のタッチ操作（2026-10-17）。ベンダリング済みappflowy_editorの
// DaiDai patch: タッチ端末では表の中に選択がある間だけ行・列ハンドルを常時表示し、
// セルの矩形範囲を選択できる。並び替え（moveRow/moveCol）の付け替えも検証する。

/// 3列×3行の表（セルのテキストは "{列}{行}"、例: c0r1 = 0列目1行目）。
EditorState _gridState() {
  final table = TableNode.fromList<String>([
    ['c0r0', 'c0r1', 'c0r2'],
    ['c1r0', 'c1r1', 'c1r2'],
    ['c2r0', 'c2r1', 'c2r2'],
  ]).node;
  return EditorState(
    document: Document(
      root: pageNode(
        children: [
          paragraphNode(text: 'before'),
          table,
        ],
      ),
    ),
  );
}

Node _table(EditorState state) => state.document.root.children.last;

Node _cell(Node table, int col, int row) => table.children.firstWhere(
  (c) =>
      c.attributes[TableCellBlockKeys.colPosition] == col &&
      c.attributes[TableCellBlockKeys.rowPosition] == row,
);

String _text(Node table, int col, int row) =>
    _cell(table, col, row).children.first.delta!.toPlainText();

void main() {
  group('行・列の並び替え', () {
    test('列を右へ動かすと、colPositionが付け替わる', () {
      final state = _gridState();
      final table = _table(state);
      final tr = state.transaction;
      TableNode(node: table).moveCol(0, 3, transaction: tr);
      state.apply(tr);
      // 0列目が末尾（2列目）に移り、元の1・2列目が繰り上がる。
      expect(_text(table, 2, 0), 'c0r0');
      expect(_text(table, 0, 0), 'c1r0');
      expect(_text(table, 1, 0), 'c2r0');
    });

    test('行を上へ動かすと、rowPositionが付け替わる', () {
      final state = _gridState();
      final table = _table(state);
      final tr = state.transaction;
      TableNode(node: table).moveRow(2, 0, transaction: tr);
      state.apply(tr);
      expect(_text(table, 0, 0), 'c0r2');
      expect(_text(table, 0, 1), 'c0r0');
      expect(_text(table, 0, 2), 'c0r1');
    });

    test('同じ位置・すぐ後ろへの移動は何も変えない', () {
      final state = _gridState();
      final table = _table(state);
      final tr = state.transaction;
      TableNode(node: table).moveCol(1, 1, transaction: tr);
      TableNode(node: table).moveCol(1, 2, transaction: tr);
      expect(tr.operations, isEmpty);
    });
  });

  group('セルの矩形選択', () {
    test('対角の2セルから、左上のセルの先頭〜右下のセルの末尾の選択になる', () {
      final state = _gridState();
      final table = _table(state);
      // 右下(列2,行2)から左上寄り(列1,行0)へ向けてドラッグした場合も、
      // 左上(列1,行0)〜右下(列2,行2)の矩形として扱う。
      final selection = TableActions.rangeSelection(table, 2, 2, 0, 1)!;
      final topLeft = _cell(table, 1, 0).children.first;
      final bottomRight = _cell(table, 2, 2).children.first;
      expect(selection.start.path, topLeft.path);
      expect(selection.start.offset, 0);
      expect(selection.end.path, bottomRight.path);
      expect(selection.end.offset, 'c2r2'.length);
    });

    test('始点と終点が同じセルなら、そのセルの全文選択', () {
      final state = _gridState();
      final table = _table(state);
      final selection = TableActions.rangeSelection(table, 1, 1, 1, 1)!;
      final leaf = _cell(table, 1, 1).children.first;
      expect(selection.start, Position(path: leaf.path));
      expect(selection.end, Position(path: leaf.path, offset: 'c1r1'.length));
    });

    test('存在しないセルを指すとnull', () {
      final state = _gridState();
      expect(TableActions.rangeSelection(_table(state), 5, 5, 0, 0), isNull);
    });
  });

  group('表を操作中かどうかの判定', () {
    test('選択が表の中にある時だけtrue', () {
      final state = _gridState();
      final table = _table(state);
      final inside = _cell(table, 0, 0).children.first;
      expect(
        isSelectionInTable(
          table,
          Selection.collapsed(Position(path: inside.path)),
        ),
        isTrue,
      );
      expect(
        isSelectionInTable(table, Selection.collapsed(Position(path: [0]))),
        isFalse,
      );
      expect(isSelectionInTable(table, null), isFalse);
    });

    test('タッチ主体のプラットフォームだけtrue', () {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(isTableTouchPlatform, isTrue);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(isTableTouchPlatform, isTrue);
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        expect(isTableTouchPlatform, isFalse);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        expect(isTableTouchPlatform, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('行・列ハンドルの表示', () {
    Future<EditorState> pumpHandle(WidgetTester tester) async {
      final state = _gridState();
      final table = _table(state);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 28,
              height: 28,
              child: TableActionHandler(
                node: table,
                editorState: state,
                position: 0,
                alignment: Alignment.center,
                transform: Matrix4.identity(),
                dir: TableDirection.col,
              ),
            ),
          ),
        ),
      );
      return state;
    }

    bool handleVisible(WidgetTester tester) =>
        tester.widget<Visibility>(find.byType(Visibility)).visible;

    testWidgets('PCではホバーしていなければ表示しない（従来どおり）', (tester) async {
      // テスト終了時の不変条件チェックの前に必ず戻す。
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final state = await pumpHandle(tester);
        final table = _table(state);
        state.selection = Selection.collapsed(
          Position(path: _cell(table, 0, 0).children.first.path),
        );
        await tester.pump();
        expect(handleVisible(tester), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('タッチ端末では表の中に選択がある間だけ常時表示する', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final state = await pumpHandle(tester);
        final table = _table(state);
        expect(handleVisible(tester), isFalse);

        state.selection = Selection.collapsed(
          Position(path: _cell(table, 0, 0).children.first.path),
        );
        await tester.pump();
        expect(handleVisible(tester), isTrue);

        state.selection = Selection.collapsed(Position(path: [0]));
        await tester.pump();
        expect(handleVisible(tester), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
