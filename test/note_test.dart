import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Note', () {
    test('fromJson/toJsonが往復する', () {
      final json = {
        'roomId': 'room1',
        'title': '議事録',
        'content': {
          'document': {
            'type': 'page',
            'children': [
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': 'こんにちは'},
                  ],
                },
              },
            ],
          },
        },
        'createdBy': 'user1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 9, 6)),
        'lastEditedBy': 'user2',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 9, 7)),
      };
      final note = Note.fromJson('note1', json);

      expect(note.noteId, 'note1');
      expect(note.roomId, 'room1');
      expect(note.title, '議事録');
      expect(note.content['document'], isA<Map>());
      expect(note.createdBy, 'user1');
      expect(note.lastEditedBy, 'user2');

      final roundTripped = Note.fromJson('note1', note.toJson());
      expect(roundTripped.title, note.title);
      expect(roundTripped.content, note.content);
      expect(roundTripped.lastEditedBy, note.lastEditedBy);
    });

    test('title/content省略時は空文字・空Mapを返す', () {
      final note = Note.fromJson('note1', {
        'roomId': 'room1',
        'createdBy': 'user1',
      });
      expect(note.title, '');
      expect(note.content, isEmpty);
      expect(note.lastEditedBy, isNull);
      expect(note.updatedAt, isNull);
    });
  });
}
