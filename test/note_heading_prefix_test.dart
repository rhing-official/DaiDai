import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Node _heading(String text, int prefixLength) => Node(
  type: HeadingBlockKeys.type,
  attributes: {
    HeadingBlockKeys.level: 1,
    HeadingBlockKeys.markdownPrefixLength: prefixLength,
    'delta': (Delta()..insert(text)).toJson(),
  },
);

Future<EditorState> _pump(WidgetTester tester, List<Node> children) async {
  final state = EditorState(
    document: Document(root: pageNode(children: children)),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 600,
          child: AppFlowyEditor(editorState: state),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Finder _richTextContaining(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().contains(text),
);

void main() {
  testWidgets('非フォーカスの見出しは「# 」を描画せず本文が左詰めになる', (tester) async {
    final state = await _pump(tester, [
      _heading('# Title', 2),
      paragraphNode(text: 'Para'),
    ]);
    // `#`は描画されない（透明にして幅を残すのではなく、描画テキストから外す）。
    expect(_richTextContaining('#'), findsNothing);
    expect(_richTextContaining('Title'), findsOneWidget);
    // Deltaは`# `を保持したまま。
    final heading = state.document.root.children.first;
    expect(heading.delta!.toPlainText(), '# Title');
    // 本文の先頭（Deltaの2）のカーソルは、通常の段落の先頭と同じ左端。
    final headingStart = heading.selectable!.getCursorRectInPosition(
      Position(path: heading.path, offset: 2),
    )!;
    final paragraph = state.document.root.children.last;
    final paragraphStart = paragraph.selectable!.getCursorRectInPosition(
      Position(path: paragraph.path, offset: 0),
    )!;
    expect(headingStart.left, closeTo(paragraphStart.left, 0.5));
  });

  testWidgets('非フォーカスの見出しの座標はDeltaのオフセットに換算される', (tester) async {
    final state = await _pump(tester, [
      _heading('# Title', 2),
      paragraphNode(text: 'Para'),
    ]);
    final heading = state.document.root.children.first;
    final selectable = heading.selectable!;
    // Deltaの末尾（7）のカーソル位置の少し左を指すと、末尾付近（6〜7）に戻る。
    final endRect = selectable.getCursorRectInPosition(
      Position(path: heading.path, offset: 7),
    )!;
    final global = selectable.localToGlobal(endRect.centerLeft);
    final position = selectable.getPositionInOffset(global.translate(-1, 0));
    expect(position.offset, inInclusiveRange(6, 7));
    // 隠した`# `の中（0）も本文の先頭（2）と同じ左端に丸められる。
    final startRect = selectable.getCursorRectInPosition(
      Position(path: heading.path, offset: 2),
    )!;
    final insideRect = selectable.getCursorRectInPosition(
      Position(path: heading.path, offset: 0),
    )!;
    expect(insideRect.left, closeTo(startRect.left, 0.5));
  });

  testWidgets('カーソルを置くと`#`が現れ、本文が右にずれる', (tester) async {
    final state = await _pump(tester, [
      _heading('# Title', 2),
      paragraphNode(text: 'Para'),
    ]);
    final heading = state.document.root.children.first;
    final before = heading.selectable!
        .getCursorRectInPosition(Position(path: heading.path, offset: 2))!
        .left;

    state.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await tester.pumpAndSettle();

    expect(_richTextContaining('# Title'), findsOneWidget);
    final after = heading.selectable!
        .getCursorRectInPosition(Position(path: heading.path, offset: 2))!
        .left;
    // 本文の先頭（2）は、`# `の幅ぶん右に移る。
    expect(after, greaterThan(before + 4));
  });

  testWidgets('箇条書きも非フォーカス時の座標がDeltaのオフセットに換算される', (tester) async {
    final bullet = Node(
      type: BulletedListBlockKeys.type,
      attributes: {
        BulletedListBlockKeys.markdownPrefixLength: 2,
        'delta': (Delta()..insert('- Item')).toJson(),
      },
    );
    final state = await _pump(tester, [bullet, paragraphNode(text: 'Para')]);
    final node = state.document.root.children.first;
    final selectable = node.selectable!;
    final endRect = selectable.getCursorRectInPosition(
      Position(path: node.path, offset: 6),
    )!;
    final global = selectable.localToGlobal(endRect.centerLeft);
    final position = selectable.getPositionInOffset(global.translate(-1, 0));
    expect(position.offset, inInclusiveRange(5, 6));
  });
}
