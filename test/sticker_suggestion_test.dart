import 'package:daidai/models/sticker.dart';
import 'package:daidai/models/sticker_role.dart';
import 'package:daidai/utils/sticker_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const happyRole = StickerRole(
    roleId: 'happy',
    name: '嬉しい',
    keywords: ['やった', 'よし'],
  );
  const thanksRole = StickerRole(
    roleId: 'thanks',
    name: '感謝',
    keywords: ['ありがとう'],
  );
  const roles = [happyRole, thanksRole];

  const happySticker = Sticker(
    stickerId: 's-happy',
    name: 'うれしい顔',
    imageUrl: 'https://example.com/happy.webp',
    roles: ['happy'],
  );
  const thanksSticker = Sticker(
    stickerId: 's-thanks',
    name: '感謝顔',
    imageUrl: 'https://example.com/thanks.webp',
    roles: ['thanks'],
  );
  const bothSticker = Sticker(
    stickerId: 's-both',
    name: '万能顔',
    imageUrl: 'https://example.com/both.webp',
    roles: ['happy', 'thanks'],
  );
  const noRoleSticker = Sticker(
    stickerId: 's-none',
    name: '無地',
    imageUrl: 'https://example.com/none.webp',
  );
  final candidates = [happySticker, thanksSticker, bothSticker, noRoleSticker];

  test('キーワードを含む文には対応する役割のペタピタが候補になる', () {
    final result = suggestStickers(
      messageText: '今日は本当にやったーー！',
      roles: roles,
      candidates: candidates,
    );
    expect(result, contains(happySticker));
    expect(result, contains(bothSticker));
    expect(result, isNot(contains(thanksSticker)));
    expect(result, isNot(contains(noRoleSticker)));
  });

  test('複数の役割にヒットしたスタンプほど上位に来る', () {
    final result = suggestStickers(
      messageText: 'やった、ありがとう！',
      roles: roles,
      candidates: candidates,
    );
    expect(result.first, bothSticker);
  });

  test('カタカナ/ひらがな・大文字小文字の表記ゆれを吸収する', () {
    const okRole = StickerRole(roleId: 'ok', name: '了解', keywords: ['OK']);
    const okSticker = Sticker(
      stickerId: 's-ok',
      name: 'OK顔',
      imageUrl: 'https://example.com/ok.webp',
      roles: ['ok'],
    );
    final result = suggestStickers(
      messageText: 'りょうかい、okです',
      roles: [okRole],
      candidates: [okSticker],
    );
    expect(result, [okSticker]);

    final katakanaResult = suggestStickers(
      messageText: 'アリガトウございます',
      roles: [thanksRole],
      candidates: [thanksSticker],
    );
    expect(katakanaResult, [thanksSticker]);
  });

  test('一致するキーワードが無ければ空リストを返す', () {
    final result = suggestStickers(
      messageText: '明日の予定を確認したい',
      roles: roles,
      candidates: candidates,
    );
    expect(result, isEmpty);
  });

  test('空文字のメッセージは空リストを返す', () {
    final result = suggestStickers(
      messageText: '',
      roles: roles,
      candidates: candidates,
    );
    expect(result, isEmpty);
  });
}
