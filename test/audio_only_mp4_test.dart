import 'dart:typed_data';

import 'package:daidai/utils/audio_only_mp4.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> box(String type, List<int> body) {
  final size = 8 + body.length;
  return [
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...type.codeUnits,
    ...body,
  ];
}

List<int> trak(String handler) => box('trak', [
  ...box('mdia', [
    ...box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...handler.codeUnits, 0, 0, 0, 0]),
  ]),
]);

Uint8List file(List<String> handlers, {bool moovLast = false}) {
  final ftyp = box('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0]);
  final moov = box('moov', [for (final h in handlers) ...trak(h)]);
  final mdat = box('mdat', List.filled(32, 1));
  return Uint8List.fromList(
    moovLast ? [...ftyp, ...mdat, ...moov] : [...ftyp, ...moov, ...mdat],
  );
}

void main() {
  group('isAudioOnlyIsoBmff', () {
    test('音声トラックだけなら真', () {
      expect(isAudioOnlyIsoBmff(file(['soun'])), isTrue);
    });
    test('moovが末尾にあっても真', () {
      expect(isAudioOnlyIsoBmff(file(['soun'], moovLast: true)), isTrue);
    });
    test('映像トラックがあれば偽', () {
      expect(isAudioOnlyIsoBmff(file(['vide', 'soun'])), isFalse);
    });
    test('壊れた入力は例外を投げず偽', () {
      expect(isAudioOnlyIsoBmff(Uint8List(0)), isFalse);
      expect(
        isAudioOnlyIsoBmff(Uint8List.fromList(List.filled(40, 7))),
        isFalse,
      );
      final truncated = file(['soun']).sublist(0, 30);
      expect(isAudioOnlyIsoBmff(truncated), isFalse);
    });
  });
}
