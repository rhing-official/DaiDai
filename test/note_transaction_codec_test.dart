import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:daidai/utils/note_transaction_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// [encodeTransaction]/[decodeTransaction]の往復テスト。
///
/// 必ず`jsonEncode`→`jsonDecode`を経由してからデコードする（Firestoreの
/// `List<dynamic>`/`Map<String, dynamic>`化を模擬するため）。appflowy_editor
/// パッケージの`InsertOperation.fromJson`等は`json['path'] as Path`
/// （`Path`は`List<int>`のtypedef）という直接キャストをしており、
/// `List<dynamic>`に対して行うと実行時型エラーになる。同種の値をそのまま
/// メモリ上で渡すだけのテストではこの問題を検出できないため、この往復を
/// 必ず経由する。
void main() {
  final document = Document.blank();

  Map<String, dynamic> roundTripJson(Transaction transaction) {
    final encoded = encodeTransaction(transaction);
    return jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
  }

  group('note_transaction_codec', () {
    test('update_text operationが往復する', () {
      final transaction = Transaction(document: document);
      transaction.operations = [
        UpdateTextOperation(
          [0],
          Delta()
            ..retain(0)
            ..insert('こんにちは'),
          Delta()..delete(5),
        ),
      ];

      final json = roundTripJson(transaction);
      final decoded = decodeTransaction(document, json);

      expect(decoded.operations, hasLength(1));
      expect(decoded.operations.single.toJson(), {
        'op': 'update_text',
        'path': [0],
        'delta': [
          {'insert': 'こんにちは'},
        ],
        'inverted': [
          {'delete': 5},
        ],
      });
    });

    test('insert operationが往復する（Node配下のchildrenを含む）', () {
      final transaction = Transaction(document: document);
      final node = paragraphNode(text: '新しい段落');
      transaction.operations = [
        InsertOperation([1], [node]),
      ];

      final json = roundTripJson(transaction);
      final decoded = decodeTransaction(document, json);

      expect(decoded.operations, hasLength(1));
      final op = decoded.operations.single as InsertOperation;
      expect(op.path, [1]);
      expect(op.nodes, hasLength(1));
      expect(op.nodes.first.type, node.type);
      expect(op.nodes.first.delta?.toPlainText(), '新しい段落');
    });

    test('delete operationが往復する', () {
      final transaction = Transaction(document: document);
      final node = paragraphNode(text: '削除される段落');
      transaction.operations = [
        DeleteOperation([2], [node]),
      ];

      final json = roundTripJson(transaction);
      final decoded = decodeTransaction(document, json);

      expect(decoded.operations, hasLength(1));
      final op = decoded.operations.single as DeleteOperation;
      expect(op.path, [2]);
      expect(op.nodes, hasLength(1));
      expect(op.nodes.first.delta?.toPlainText(), '削除される段落');
    });

    test('update operationが往復する', () {
      final transaction = Transaction(document: document);
      transaction.operations = [
        UpdateOperation([0], {'align': 'center'}, {'align': 'left'}),
      ];

      final json = roundTripJson(transaction);
      final decoded = decodeTransaction(document, json);

      expect(decoded.operations, hasLength(1));
      expect(decoded.operations.single.toJson(), {
        'op': 'update',
        'path': [0],
        'attributes': {'align': 'center'},
        'oldAttributes': {'align': 'left'},
      });
    });

    test('深いpath（ネストしたブロック）も正しく整数リストへ正規化される', () {
      final transaction = Transaction(document: document);
      transaction.operations = [
        UpdateTextOperation([2, 1, 0], Delta()..insert('x'), Delta()),
      ];

      final json = roundTripJson(transaction);
      final decoded = decodeTransaction(document, json);

      expect(decoded.operations.single.path, [2, 1, 0]);
    });
  });
}
