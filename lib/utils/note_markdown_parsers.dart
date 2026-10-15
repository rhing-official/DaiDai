import 'package:appflowy_editor/appflowy_editor.dart';

import '../features/note/blocks/table_of_contents_block.dart';

/// 目次ブロックを`.md`へ書き出すとき、他のアプリで開いても素のコードブロック
/// として読めるよう、言語名付きのコードフェンスに寄せる。Obsidianの
/// プラグイン`daidai-toc`は、このフェンスを見出しから生成した目次として
/// 描画する。見出し自体は通常の`#`として別に書き出されるため、フェンスの
/// 中身は空でよい。
const String tableOfContentsMarkdownFence = 'daidai-toc';

class TableOfContentsNodeParser extends NodeParser {
  const TableOfContentsNodeParser();

  @override
  String get id => TableOfContentsBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    return '```$tableOfContentsMarkdownFence\n```\n';
  }
}

/// 見出し・箇条書きは、入力時の`### `や`- `を削除せずDeltaに残す設計
/// （`markdownPrefixLength`属性、カーソル行のみ表示）。標準のパーサは本文に
/// 記号が無い前提でもう一度記号を付けるため、そのままでは`### ### c`のように
/// 二重になる。属性がある場合は先頭の記号を除いてから書き出す。
Delta _withoutMarkdownPrefix(Node node, String key) {
  final delta = node.delta ?? (Delta()..insert(''));
  final prefixLength = node.attributes[key] as int?;
  if (prefixLength == null || prefixLength > delta.length) return delta;
  return delta.slice(prefixLength);
}

class NoteHeadingNodeParser extends NodeParser {
  const NoteHeadingNodeParser();

  @override
  String get id => HeadingBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = _withoutMarkdownPrefix(
      node,
      HeadingBlockKeys.markdownPrefixLength,
    );
    final level = node.attributes[HeadingBlockKeys.level] as int? ?? 1;
    final suffix = node.next == null ? '' : '\n';
    return '${'#' * level} ${DeltaMarkdownEncoder().convert(delta)}$suffix';
  }
}

class NoteBulletedListNodeParser extends NodeParser {
  const NoteBulletedListNodeParser();

  @override
  String get id => BulletedListBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = _withoutMarkdownPrefix(
      node,
      BulletedListBlockKeys.markdownPrefixLength,
    );
    final children = encoder?.convertNodes(node.children, withIndent: true);
    var markdown = '* ${DeltaMarkdownEncoder().convert(delta)}\n';
    if (children != null && children.isNotEmpty) markdown += children;
    return markdown;
  }
}

/// `documentToMarkdown`の`customParsers`へ渡す、DaiDai独自の書き出し。
const List<NodeParser> noteMarkdownCustomParsers = [
  TableOfContentsNodeParser(),
  NoteHeadingNodeParser(),
  NoteBulletedListNodeParser(),
];
