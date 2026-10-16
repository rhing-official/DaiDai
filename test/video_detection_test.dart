import 'dart:typed_data';

import 'package:daidai/utils/attachment_upload.dart';
import 'package:flutter_test/flutter_test.dart';

// 複数選択で動画が画像として送られていた不具合の回帰テスト（2026-10-16）。
Uint8List _ftyp(String brand) => Uint8List.fromList([
  0,
  0,
  0,
  24,
  ...'ftyp'.codeUnits,
  ...brand.codeUnits,
  0,
  0,
  0,
  0,
]);

void main() {
  group('isVideoFileName', () {
    test('mimeTypeがvideo/・image/なら、それを信じる', () {
      expect(isVideoFileName('a', mimeType: 'video/mp4'), isTrue);
      expect(isVideoFileName('a.mp4', mimeType: 'image/jpeg'), isFalse);
    });

    test('mimeTypeがnull・空・octet-streamなら拡張子で判定する', () {
      for (final mime in [null, '', 'application/octet-stream']) {
        expect(isVideoFileName('clip.MOV', mimeType: mime), isTrue);
        expect(isVideoFileName('clip.m4v', mimeType: mime), isTrue);
        expect(isVideoFileName('photo.jpg', mimeType: mime), isFalse);
        expect(isVideoFileName('noextension', mimeType: mime), isFalse);
      }
    });
  });

  group('looksLikeVideoBytes', () {
    test('mp4・mov・3gpは動画', () {
      expect(looksLikeVideoBytes(_ftyp('isom')), isTrue);
      expect(looksLikeVideoBytes(_ftyp('mp42')), isTrue);
      expect(looksLikeVideoBytes(_ftyp('qt  ')), isTrue);
      expect(looksLikeVideoBytes(_ftyp('3gp4')), isTrue);
    });

    test('HEIC・AVIFは画像（動画にしない）', () {
      expect(looksLikeVideoBytes(_ftyp('heic')), isFalse);
      expect(looksLikeVideoBytes(_ftyp('avif')), isFalse);
      expect(looksLikeVideoBytes(_ftyp('mif1')), isFalse);
    });

    test('webm/mkv（EBML）とaviは動画', () {
      final ebml = Uint8List.fromList([
        0x1A,
        0x45,
        0xDF,
        0xA3,
        ...List.filled(12, 0),
      ]);
      expect(looksLikeVideoBytes(ebml), isTrue);
      final avi = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'AVI '.codeUnits,
      ]);
      expect(looksLikeVideoBytes(avi), isTrue);
    });

    test('PNG・JPEG・短いデータは動画ではない', () {
      expect(
        looksLikeVideoBytes(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(16, 0)]),
        ),
        isFalse,
      );
      expect(
        looksLikeVideoBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(16, 0)]),
        ),
        isFalse,
      );
      expect(looksLikeVideoBytes(Uint8List(4)), isFalse);
    });
  });
}
