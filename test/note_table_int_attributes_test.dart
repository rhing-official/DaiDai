import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('数値が整数で保存された表でも型のエラーにならない', (tester) async {
    tester.view.physicalSize = const Size(705, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final tableNode = TableNode.fromList<String>(
      List.generate(3, (_) => List.generate(3, (_) => 'a')),
    ).node;
    // 保存データ（Firestore由来）を想定して、数値をすべて整数にする。
    tableNode.updateAttributes({TableBlockKeys.colsHeight: 120});
    for (final cell in tableNode.children) {
      cell.updateAttributes({
        TableCellBlockKeys.width: 160,
        TableCellBlockKeys.height: 40,
      });
    }
    final doc = Document.blank()
      ..insert([0], [paragraphNode(text: 'x'), tableNode]);
    final state = EditorState(document: doc);
    final sc = EditorScrollController(editorState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            editorScrollController: sc,
            editorStyle: EditorStyle.mobile(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 数値が整数で保存された表でも、型のエラー（`int`は`double?`ではない）にならない。
    // ネイティブ（Android）では`int`と`double`が別の型で、Webでは同じため、Webだけ通っていた
    // （2026-11-15、ノートが灰色のエラー表示になる不具合）。画面の溢れなど他の警告は対象外。
    final error = tester.takeException();
    expect(error?.toString() ?? '', isNot(contains('is not a subtype')));
  });
}
