import 'package:daidai/models/soundboard_sound.dart';
import 'package:flutter_test/flutter_test.dart';

SoundboardSound _s(String id, String name, {String by = 'u'}) =>
    SoundboardSound(
      soundId: id,
      name: name,
      storagePath: 'p/$id',
      mimeType: 'audio/mpeg',
      createdBy: by,
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

  group('soundboardLimitFor', () {
    test('無料は5個、極みは10個', () {
      expect(soundboardLimitFor(kiwami: false), 5);
      expect(soundboardLimitFor(kiwami: true), 10);
    });
  });

  group('composeSoundboardSounds', () {
    final mine = [_s('m1', 'mine1', by: 'me'), _s('m2', 'mine2', by: 'me')];

    test('自分の音は、どの語らいでも「マイサウンド」に出る', () {
      final lists = composeSoundboardSounds(
        userId: 'me',
        mine: mine,
        inConversation: const [],
      );
      expect([for (final s in lists.mine) s.soundId], ['m1', 'm2']);
      expect(lists.shared, isEmpty);
    });

    test('語らいに登録された、マイサウンドと同じidの参照は重ねて出さない', () {
      final lists = composeSoundboardSounds(
        userId: 'me',
        mine: mine,
        inConversation: [
          _s('m1', 'mine1', by: 'me'),
          _s('o1', 'other', by: 'you'),
        ],
      );
      expect([for (final s in lists.shared) s.soundId], ['o1']);
      expect([for (final s in lists.all) s.soundId], ['m1', 'm2', 'o1']);
    });

    test('広場では、追加した人が今のメンバーでない音は出さない', () {
      final lists = composeSoundboardSounds(
        userId: 'me',
        mine: const [],
        inConversation: [
          _s('o1', 'stay', by: 'you'),
          _s('o2', 'left', by: 'gone'),
        ],
        memberIds: {'me', 'you'},
      );
      expect([for (final s in lists.shared) s.soundId], ['o1']);
    });

    test('一対（メンバーの指定なし）は、相手の音をそのまま出す', () {
      final lists = composeSoundboardSounds(
        userId: 'me',
        mine: const [],
        inConversation: [_s('o1', 'a', by: 'you')],
      );
      expect(lists.shared.length, 1);
    });

    test('以前の（語らい単位の）自分の音は、メンバー判定に関わらず「この語らい」に出る', () {
      final lists = composeSoundboardSounds(
        userId: 'me',
        mine: const [],
        inConversation: [_s('old', 'old', by: 'me')],
        memberIds: {'you'},
      );
      expect([for (final s in lists.shared) s.soundId], ['old']);
    });
  });

  test('個人保存の音は、保存先のパスで見分ける', () {
    expect(_s('1', 'a').isPersonal, isFalse);
    final personal = SoundboardSound(
      soundId: '1',
      name: 'a',
      storagePath: 'soundboard/user/me/1/audio.mp3',
      mimeType: 'audio/mpeg',
      createdBy: 'me',
    );
    expect(personal.isPersonal, isTrue);
  });
}
