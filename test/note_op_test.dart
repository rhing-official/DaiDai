import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/note_op.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteOp', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'transactions': [
          {
            'operations': [
              {
                'op': 'update_text',
                'path': [0],
                'delta': [
                  {'insert': 'こんにちは'},
                ],
                'inverted': [
                  {'delete': 5},
                ],
              },
            ],
          },
        ],
        'sessionId': 'session1',
        'authorId': 'user1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 9)),
      };
      final op = NoteOp.fromJson('op1', json);

      expect(op.opId, 'op1');
      expect(op.transactions, hasLength(1));
      expect(op.sessionId, 'session1');
      expect(op.authorId, 'user1');
      expect(op.createdAt, isNotNull);

      final roundTripped = NoteOp.fromJson('op1', op.toJson());
      expect(roundTripped.transactions, op.transactions);
      expect(roundTripped.sessionId, op.sessionId);
      expect(roundTripped.authorId, op.authorId);
    });

    test('transactions省略時は空リストを返す', () {
      final op = NoteOp.fromJson('op1', {
        'sessionId': 'session1',
        'authorId': 'user1',
      });
      expect(op.transactions, isEmpty);
      expect(op.createdAt, isNull);
    });
  });
}
