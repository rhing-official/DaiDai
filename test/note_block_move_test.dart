import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/features/note/block_move_drag.dart';
import 'package:daidai/features/note/blocks/table_of_contents_block.dart';
import 'package:daidai/utils/note_transaction_codec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blockInsertIndex', () {
    const blocks = [
      VisibleBlock(index: 0, top: 0, bottom: 40),
      VisibleBlock(index: 1, top: 40, bottom: 120),
      VisibleBlock(index: 2, top: 120, bottom: 160),
    ];

    test('各ブロックの上半分なら「そのブロックの前」', () {
      expect(blockInsertIndex(blocks, 5), 0);
      expect(blockInsertIndex(blocks, 50), 1);
      expect(blockInsertIndex(blocks, 125), 2);
    });

    test('下半分なら次のブロックの前、最後の下なら末尾', () {
      expect(blockInsertIndex(blocks, 30), 1);
      expect(blockInsertIndex(blocks, 110), 2);
      expect(blockInsertIndex(blocks, 150), 3);
      expect(blockInsertIndex(blocks, 999), 3);
    });

    test('表示中のブロックが無ければ0', () {
      expect(blockInsertIndex(const [], 100), 0);
    });
  });

  group('blockMoveTargetIndex', () {
    test('moveNodeには移動前の挿入位置をそのまま渡す（補正はTransactionがする）', () {
      expect(blockMoveTargetIndex(0, 3), 3);
      expect(blockMoveTargetIndex(2, 0), 0);
    });

    test('同じ位置（自分の前・後ろ）なら移動しない', () {
      expect(blockMoveTargetIndex(2, 2), isNull);
      expect(blockMoveTargetIndex(2, 3), isNull);
    });

    test('移動後の実際のインデックス', () {
      expect(blockFinalIndex(0, 3), 2);
      expect(blockFinalIndex(2, 0), 0);
    });
  });

  group('moveNode（目次・表）', () {
    EditorState build() => EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'a'),
            tableOfContentsNode(),
            paragraphNode(text: 'b'),
            TableNode.fromList<String>([
              ['x', 'y'],
              ['z', 'w'],
            ]).node,
          ],
        ),
      ),
    );

    List<String> types(EditorState s) =>
        s.document.root.children.map((n) => n.type).toList();

    test('目次を末尾へ移動でき、取り消しで元に戻る', () async {
      final state = build();
      final toc = state.document.root.children[1];
      final to = blockMoveTargetIndex(1, 4)!;
      expect(to, 4);
      await state.apply(state.transaction..moveNode([to], toc));

      expect(types(state), [
        ParagraphBlockKeys.type,
        ParagraphBlockKeys.type,
        TableBlockKeys.type,
        TableOfContentsBlockKeys.type,
      ]);

      undoCommand.execute(state);
      expect(types(state), [
        ParagraphBlockKeys.type,
        TableOfContentsBlockKeys.type,
        ParagraphBlockKeys.type,
        TableBlockKeys.type,
      ]);
    });

    test('表を先頭へ移動しても中身（セル）が保たれる', () async {
      final state = build();
      final table = state.document.root.children[3];
      await state.apply(state.transaction..moveNode([0], table));

      expect(state.document.root.children.first.type, TableBlockKeys.type);
      final cells = state.document.root.children.first.children;
      expect(cells.length, 4);
      expect(cells.map((c) => c.children.first.delta!.toPlainText()).toSet(), {
        'x',
        'y',
        'z',
        'w',
      });
    });

    test('移動の操作ログをJSON経由で別端末へ適用しても同じ結果になる', () async {
      final sender = build();
      final receiver = build();
      final toc = sender.document.root.children[1];
      final transaction = sender.transaction..moveNode([3], toc);
      // Firestoreを経由した読み返し（List<dynamic>/Map<String, dynamic>）を模す。
      final wire =
          jsonDecode(jsonEncode(encodeTransaction(transaction)))
              as Map<String, dynamic>;
      await sender.apply(transaction);

      await receiver.apply(decodeTransaction(receiver.document, wire));

      expect(types(receiver), types(sender));
    });
  });

  group('BlockMoveHandle（エディタ全体のドラッグ選択と競合しても勝つ）', () {
    Future<EditorState> pump(
      WidgetTester tester, {
      void Function(Offset)? onTap,
      PointerDeviceKind kind = PointerDeviceKind.mouse,
    }) async {
      final state = EditorState(
        document: Document(
          root: pageNode(
            children: [
              paragraphNode(text: 'a'),
              tableOfContentsNode(),
              paragraphNode(text: 'b'),
            ],
          ),
        ),
      );
      state.editorStyle = EditorStyle.desktop();
      var selectionDragStarted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RawGestureDetector(
            gestures: {
              ImmediateMultiDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    ImmediateMultiDragGestureRecognizer
                  >(ImmediateMultiDragGestureRecognizer.new, (r) {
                    r.onStart = (_) {
                      selectionDragStarted = true;
                      return _NoopDrag();
                    };
                  }),
            },
            child: Center(
              child: BlockMoveHandle(
                node: state.document.root.children[1],
                editorState: state,
                color: Colors.black,
                onTap: onTap,
                child: const SizedBox(width: 200, height: 80),
              ),
            ),
          ),
        ),
      );
      addTearDown(() => expect(selectionDragStarted, isFalse));
      return state;
    }

    testWidgets('マウスで動かさず離すとonTapが呼ばれる', (tester) async {
      Offset? tapped;
      await pump(tester, onTap: (p) => tapped = p);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BlockMoveHandle)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      expect(tapped, isNotNull);
    });

    testWidgets('マウスでドラッグしても選択側ではなくハンドルが勝つ', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BlockMoveHandle)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.up();
    });
  });
}

class _NoopDrag extends Drag {}
