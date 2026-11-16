import 'package:daidai/models/soundboard_sound.dart';
import 'package:flutter_test/flutter_test.dart';

SoundboardSound _s(String id, String name) => SoundboardSound(
  soundId: id,
  name: name,
  storagePath: 'p/$id',
  mimeType: 'audio/mpeg',
  createdBy: 'u',
);

void main() {
  group('filterSoundboardSounds', () {
    final sounds = [
      _s('1', 'Golf Clap'),
      _s('2', 'sad horn'),
      _s('3', 'ba dum'),
    ];

    test('空の検索語は全て返す', () {
      expect(filterSoundboardSounds(sounds, '  '), sounds);
    });

    test('大文字小文字を区別せず、名前の一部で絞り込む', () {
      expect(
        [for (final s in filterSoundboardSounds(sounds, 'HORN')) s.soundId],
        ['2'],
      );
      expect(filterSoundboardSounds(sounds, 'zzz'), isEmpty);
    });
  });

  test('音量の既定は最大', () {
    expect(_s('1', 'a').volume, 1.0);
  });
}
