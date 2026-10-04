import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/note.dart';
import 'package:daidai/models/note_stroke.dart';
import 'package:daidai/utils/note_export.dart';

void main() {
  test('typeフィールドが無い既存ノートはマークダウン扱い', () {
    final note = Note.fromJson('n1', {'roomId': 'r', 'createdBy': 'u'});
    expect(note.type, noteTypeMarkdown);
  });

  test('ドローノートのtypeを読み書きできる', () {
    final note = Note.fromJson('n1', {
      'roomId': 'r',
      'createdBy': 'u',
      'type': 'draw',
    });
    expect(note.type, noteTypeDraw);
    expect(note.toJson()['type'], 'draw');
  });

  test('NoteStrokeの外接矩形と当たり判定', () {
    const stroke = NoteStroke(
      strokeId: 's',
      points: [0, 0, 100, 0],
      color: 0xFF000000,
      width: 10,
      authorId: 'u',
    );
    expect(stroke.pointCount, 2);
    expect(stroke.bounds, const Rect.fromLTRB(-5, -5, 105, 5));
    expect(stroke.hitTest(const Offset(50, 8), 5), isTrue);
    expect(stroke.hitTest(const Offset(50, 40), 5), isFalse);
  });

  test('線が無ければPNGはnull、あればPNGシグネチャで始まる', () async {
    expect(await renderStrokesToPng(const []), isNull);
    const stroke = NoteStroke(
      strokeId: 's',
      points: [0, 0, 100, 50],
      color: 0xFF000000,
      width: 4,
      authorId: 'u',
    );
    final png = await renderStrokesToPng(const [stroke]);
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('ファイル名の禁止文字を置換し、空ならフォールバック', () {
    expect(sanitizeFileName('a/b:c', 'x'), 'a_b_c');
    expect(sanitizeFileName('  ', 'x'), 'x');
  });
}
