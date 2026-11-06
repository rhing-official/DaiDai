import 'package:daidai/features/call/bgm/call_bgm_sheet.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/group_call.dart';
import 'package:daidai/models/group_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CallParticipant: bgmTitleを読み書き出来る（無ければnull）', () {
    final withBgm = CallParticipant.fromJson('u1', {
      'rhingSeed': 'a',
      'bgmTitle': '曲A',
    });
    expect(withBgm.bgmTitle, '曲A');
    expect(withBgm.toJson()['bgmTitle'], '曲A');

    final without = CallParticipant.fromJson('u2', {'rhingSeed': 'b'});
    expect(without.bgmTitle, isNull);
    expect(without.toJson().containsKey('bgmTitle'), isFalse);
  });

  test('GroupPermission.playBgm: 権限一覧に含まれ、日英のラベルがある', () {
    expect(GroupPermission.all, contains(GroupPermission.playBgm));
    expect(
      Strings.of(
        AppLocale.japanese,
      ).groupPermissionLabel(GroupPermission.playBgm),
      isNot(GroupPermission.playBgm),
    );
    expect(
      Strings.of(
        AppLocale.britishEnglish,
      ).groupPermissionLabel(GroupPermission.playBgm),
      isNot(GroupPermission.playBgm),
    );
  });

  test('bgmMimeTypeFor・bgmDisplayName', () {
    expect(bgmMimeTypeFor('a.MP3'), 'audio/mpeg');
    expect(bgmMimeTypeFor('a.flac'), 'audio/flac');
    expect(bgmMimeTypeFor('noext'), 'audio/mpeg');
    expect(bgmDisplayName('my.song.mp3'), 'my.song');
    expect(bgmDisplayName('noext'), 'noext');
  });
}
