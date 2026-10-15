import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/features/note/blocks/table_of_contents_block.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState _state(List<Node> children, Selection selection) {
  final state = EditorState(
    document: Document(root: pageNode(children: children)),
  );
  state.selection = selection;
  return state;
}

List<String> _types(EditorState state) => [
  for (final n in state.document.root.children) n.type,
];

void main() {
  test('空の段落で挿入すると、目次と空の段落になり、カーソルは段落に置かれる', () {
    final state = _state([
      paragraphNode(text: '本文'),
      paragraphNode(),
    ], Selection.collapsed(Position(path: [1])));

    expect(insertTableOfContentsAfterSelection(state), isTrue);

    expect(_types(state), [
      ParagraphBlockKeys.type,
      TableOfContentsBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(state.selection, Selection.collapsed(Position(path: [2])));
  });

  test('文字入りの段落の後ろに挿入すると、元の段落を残して目次と空の段落が続く', () {
    final state = _state([
      paragraphNode(text: '本文'),
    ], Selection.collapsed(Position(path: [0], offset: 2)));

    expect(insertTableOfContentsAfterSelection(state), isTrue);

    expect(_types(state), [
      ParagraphBlockKeys.type,
      TableOfContentsBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(state.getNodeAtPath([0])?.delta?.toPlainText(), '本文');
    expect(state.selection, Selection.collapsed(Position(path: [2])));
  });

  test('範囲選択のときは何も変更しない', () {
    final state = _state([
      paragraphNode(text: '本文'),
    ], Selection.single(path: [0], startOffset: 0, endOffset: 2));

    expect(insertTableOfContentsAfterSelection(state), isFalse);
    expect(_types(state), [ParagraphBlockKeys.type]);
  });

  group('目次ブロックにカーソルが乗ったとき', () {
    List<Node> doc() => [
      paragraphNode(text: '上'),
      tableOfContentsNode(),
      paragraphNode(text: '下'),
    ];

    test('下へ進んでいたなら、次の行の先頭へ移す', () async {
      final state = _state(doc(), Selection.collapsed(Position(path: [1])));
      moveCaretOffTableOfContents(state, [0]);
      await Future<void>.delayed(Duration.zero);
      expect(state.selection, Selection.collapsed(Position(path: [2])));
    });

    test('上へ進んでいたなら、前の行の末尾へ移す', () async {
      final state = _state(doc(), Selection.collapsed(Position(path: [1])));
      moveCaretOffTableOfContents(state, [2]);
      await Future<void>.delayed(Duration.zero);
      expect(
        state.selection,
        Selection.collapsed(Position(path: [0], offset: 1)),
      );
    });

    test('目次が末尾なら、空の段落を足してそこへ置く', () async {
      final state = _state([
        paragraphNode(text: '上'),
        tableOfContentsNode(),
      ], Selection.collapsed(Position(path: [1])));
      moveCaretOffTableOfContents(state, [0]);
      await Future<void>.delayed(Duration.zero);
      expect(_types(state), [
        ParagraphBlockKeys.type,
        TableOfContentsBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(state.selection, Selection.collapsed(Position(path: [2])));
    });

    test('目次以外の行にカーソルがあるときは何もしない', () async {
      final state = _state(doc(), Selection.collapsed(Position(path: [0])));
      moveCaretOffTableOfContents(state, null);
      await Future<void>.delayed(Duration.zero);
      expect(state.selection, Selection.collapsed(Position(path: [0])));
      expect(_types(state).length, 3);
    });
  });
}
