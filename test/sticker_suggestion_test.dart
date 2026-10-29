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

  test('キーワードを含む文には対応する役割のぺったんが候補になる', () {
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

  group('略語・打ちかけの一致（3文字以上のキーワードは先頭2文字）', () {
    const congratsRole = StickerRole(
      roleId: 'congrats',
      name: 'お祝い',
      keywords: ['おめでとう', '祝'],
    );
    const congratsSticker = Sticker(
      stickerId: 's-congrats',
      name: 'お祝い顔',
      imageUrl: 'https://example.com/congrats.webp',
      roles: ['congrats'],
    );
    final congratsCandidates = [congratsSticker];

    List<Sticker> suggest(String text, List<StickerRole> rs) => suggestStickers(
          messageText: text,
          roles: rs,
          candidates: congratsCandidates,
        );

    test('「おめ」だけでも「おめでとう」の候補が出る', () {
      expect(suggest('おめ', [congratsRole]), [congratsSticker]);
      expect(suggest('おめー！', [congratsRole]), [congratsSticker]);
    });

    test('カタカナの「オメ」でも出る', () {
      expect(suggest('オメ', [congratsRole]), [congratsSticker]);
    });

    test('先頭以外の2文字（「とう」）では出ない', () {
      const thanks = StickerRole(
        roleId: 'thanks',
        name: '感謝',
        keywords: ['ありがとう'],
      );
      // 「ありがとう」の「とう」が、「おめでとう」に一致しないこと
      expect(suggest('ありがとう', [congratsRole, thanks]), isEmpty);
    });

    test('1文字だけでは、略語の一致にならない', () {
      expect(suggest('お', [congratsRole]), isEmpty);
    });

    test('1〜2文字のキーワードは、まるごと一致のみ', () {
      const shortRole = StickerRole(
        roleId: 'ok',
        name: '了解',
        keywords: ['りょ'],
      );
      const okSticker = Sticker(
        stickerId: 's-ok',
        name: 'OK顔',
        imageUrl: 'https://example.com/ok.webp',
        roles: ['ok'],
      );
      expect(
        suggestStickers(
          messageText: 'り',
          roles: [shortRole],
          candidates: [okSticker],
        ),
        isEmpty,
      );
      expect(
        suggestStickers(
          messageText: 'りょ',
          roles: [shortRole],
          candidates: [okSticker],
        ),
        [okSticker],
      );
    });

    test('3文字目以降が食い違う別の言葉（「おめん」「おめでたい」）では出ない', () {
      expect(suggest('おめん', [congratsRole]), isEmpty);
      expect(suggest('おめでたい', [congratsRole]), isEmpty);
      expect(suggest('今日はおめんをかぶった', [congratsRole]), isEmpty);
    });

    test('途中まで打った状態・伸ばし棒・記号つきなら出る', () {
      expect(suggest('おめで', [congratsRole]), [congratsSticker]);
      expect(suggest('おめでと', [congratsRole]), [congratsSticker]);
      expect(suggest('おめでとー', [congratsRole]), [congratsSticker]);
      expect(suggest('おめ！', [congratsRole]), [congratsSticker]);
      expect(suggest('おめ ありがとう', [congratsRole]), [congratsSticker]);
      expect(suggest('今日はおめ', [congratsRole]), [congratsSticker]);
    });

    test('keywordMatchesは、まるごと一致・先頭2文字の一致を判定する', () {
      expect(keywordMatches('おめでとう', 'おめでとう'), isTrue);
      expect(keywordMatches('おめ', 'おめでとう'), isTrue);
      expect(keywordMatches('めでたい', 'おめでとう'), isFalse);
      expect(keywordMatches('おめん', 'おめでとう'), isFalse);
      expect(keywordMatches('おめー', 'おめでとう'), isTrue);
      expect(keywordMatches('', 'おめでとう'), isFalse);
    });
  });
}
