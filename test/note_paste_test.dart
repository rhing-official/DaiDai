import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/features/note/blocks/table_of_contents_block.dart';
import 'package:daidai/utils/note_paste.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikeMarkdownBlocks', () {
    test('見出し行を含む複数行はtrue', () {
      expect(looksLikeMarkdownBlocks('# 見出し\n本文'), isTrue);
    });
    test('箇条書き行を含む複数行はtrue', () {
      expect(looksLikeMarkdownBlocks('本文\n- 項目'), isTrue);
    });
    test('記号の無い複数行はfalse', () {
      expect(looksLikeMarkdownBlocks('一行目\n二行目'), isFalse);
    });
    test('1行だけならfalse', () {
      expect(looksLikeMarkdownBlocks('# 見出し'), isFalse);
    });
    test('Markdownの表（区切り行あり）を含む複数行はtrue', () {
      expect(
        looksLikeMarkdownBlocks('| ao | aa |\n| --- | --- |\n| 1 | 2 |'),
        isTrue,
      );
    });
    test('#の直後に空白が無いものは見出しとみなさない', () {
      expect(looksLikeMarkdownBlocks('#タグ\n本文'), isFalse);
    });
  });

  test('Markdownとして貼ると、見出しが見出しブロックになる', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    state.selection = Selection.collapsed(Position(path: [0]));

    await pasteMarkdownBlocks(state, '# 見出し\n\n本文');

    final types = [for (final n in state.document.root.children) n.type];
    expect(types.first, HeadingBlockKeys.type);
    expect(state.document.root.children.first.delta?.toPlainText(), '見出し');
  });

  group('表・目次の取り込み', () {
    const tableMd =
        '| ao | aa |\n| --- | --- |\n| 1 | 2 |\n\n```daidai-toc\n```\n';

    test('目次のコードフェンスだけでもMarkdownのブロックとみなす', () {
      expect(looksLikeMarkdownBlocks('本文\n```daidai-toc\n```\n'), isTrue);
    });

    test('表と目次フェンスを、表ブロックと目次ブロックへ変換する', () {
      final types = [for (final n in markdownToNoteNodes(tableMd)) n.type];
      expect(types, [TableBlockKeys.type, TableOfContentsBlockKeys.type]);
    });

    test('貼る表には描画に必要な高さの属性が入る', () {
      final table = markdownToNoteNodes(tableMd).first;
      final height = table.attributes[TableBlockKeys.colsHeight];
      expect(height, isA<double>());
      expect(height as double, greaterThan(0));
    });

    test('空の段落で表を貼ると、表と空の段落になりカーソルは段落に置かれる', () async {
      final state = EditorState(
        document: Document(
          root: pageNode(
            children: [
              paragraphNode(text: '前'),
              paragraphNode(),
            ],
          ),
        ),
      );
      state.selection = Selection.collapsed(Position(path: [1]));
      await pasteMarkdownBlocks(state, tableMd);
      final types = [for (final n in state.document.root.children) n.type];
      expect(types, [
        ParagraphBlockKeys.type,
        TableBlockKeys.type,
        TableOfContentsBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(state.selection, Selection.collapsed(Position(path: [3])));
    });

    test('文字入りの段落の後ろへ貼ると、元の段落を残して挿入する', () async {
      final state = EditorState(
        document: Document(
          root: pageNode(children: [paragraphNode(text: '前')]),
        ),
      );
      state.selection = Selection.collapsed(Position(path: [0], offset: 1));
      await pasteMarkdownBlocks(state, tableMd);
      final types = [for (final n in state.document.root.children) n.type];
      expect(types.first, ParagraphBlockKeys.type);
      expect(types, contains(TableBlockKeys.type));
      expect(types.last, ParagraphBlockKeys.type);
    });
  });
}
