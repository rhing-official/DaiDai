import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/features/note/blocks/table_of_contents_block.dart';
import 'package:daidai/utils/note_markdown_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

Node _heading(String text, int level) => Node(
  type: HeadingBlockKeys.type,
  attributes: {
    HeadingBlockKeys.level: level,
    'delta': (Delta()..insert(text)).toJson(),
  },
);

void main() {
  test('目次ブロックはdaidai-tocのコードフェンスとして書き出される', () {
    final document = Document(
      root: pageNode(children: [tableOfContentsNode(), _heading('はじめに', 1)]),
    );
    final markdown = documentToMarkdown(
      document,
      customParsers: noteMarkdownCustomParsers,
    );
    expect(markdown, contains('```daidai-toc\n```\n'));
    expect(markdown, contains('# はじめに'));
  });

  test('目次が無い文書の出力は独自パーサの有無で変わらない', () {
    final document = Document(
      root: pageNode(children: [_heading('はじめに', 1), _heading('詳細', 2)]),
    );
    expect(
      documentToMarkdown(document, customParsers: noteMarkdownCustomParsers),
      documentToMarkdown(document),
    );
  });

  test('見出しの先頭の#を本文に保持していても、書き出しで二重にならない', () {
    final document = Document(
      root: pageNode(
        children: [
          Node(
            type: HeadingBlockKeys.type,
            attributes: {
              HeadingBlockKeys.level: 3,
              HeadingBlockKeys.markdownPrefixLength: 4,
              'delta': (Delta()..insert('### c')).toJson(),
            },
          ),
        ],
      ),
    );
    expect(
      documentToMarkdown(document, customParsers: noteMarkdownCustomParsers),
      '### c',
    );
  });

  test('箇条書きの先頭の記号を本文に保持していても、書き出しで二重にならない', () {
    final document = Document(
      root: pageNode(
        children: [
          Node(
            type: BulletedListBlockKeys.type,
            attributes: {
              BulletedListBlockKeys.markdownPrefixLength: 2,
              'delta': (Delta()..insert('- 項目')).toJson(),
            },
          ),
        ],
      ),
    );
    expect(
      documentToMarkdown(document, customParsers: noteMarkdownCustomParsers),
      '* 項目\n',
    );
  });
}
