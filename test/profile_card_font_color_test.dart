import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/user_invite_preview.dart';
import 'package:daidai/utils/color_presets.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('文字色は保存・復元でき、未指定なら保存しない', () {
    const card = ProfileCard(id: 'c', name: 'n', fontColorArgb: 0xFFA997C6);
    final json = card.toJson();
    expect(json['fontColor'], 0xFFA997C6);
    expect(ProfileCard.fromJson(json).fontColor, const Color(0xFFA997C6));
    expect(
      const ProfileCard(id: 'c', name: 'n').toJson().containsKey('fontColor'),
      isFalse,
    );
    expect(card.copyWith(clearFontColor: true).fontColorArgb, isNull);
  });

  test('招待プレビューは文字色があれば含め、無ければ従来のまま', () {
    final plain = UserInvitePreview.fromUser(
      const AppUser(userId: 'u', rhingSeed: 's'),
    );
    expect(plain.toJson().containsKey('fontColor'), isFalse);
    final colored = UserInvitePreview.fromUser(
      const AppUser(
        userId: 'u',
        rhingSeed: 's',
        profileCards: [
          ProfileCard(id: 'c', name: 'n', fontColorArgb: 0xFF112233),
        ],
        activeProfileCardId: 'c',
      ),
    );
    expect(colored.toJson()['fontColor'], 0xFF112233);
    expect(colored.version, isNot(plain.version));
  });

  testWidgets('カード内の呼び名・一言は選んだ文字色で出る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileCardView(
            width: 400,
            height: 500,
            nickname: 'なまえ',
            statusMessage: 'ひとこと',
            fontColor: Color(0xFF123456),
          ),
        ),
      ),
    );
    final nick = tester.widget<Text>(find.text('なまえ'));
    final status = tester.widget<Text>(find.text('ひとこと'));
    expect(nick.style?.color, const Color(0xFF123456));
    expect(status.style?.color?.a, closeTo(0.75, 0.01));
    expect(status.style?.color?.r, closeTo(0x12 / 255, 0.01));
  });

  testWidgets('文字色が未指定なら標準の白（背景の有無によらず）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileCardView(
            width: 400,
            height: 500,
            nickname: 'なまえ',
            statusMessage: 'ひとこと',
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('なまえ')).style?.color, Colors.white);
    expect(
      tester.widget<Text>(find.text('ひとこと')).style?.color?.a,
      closeTo(0.75, 0.01),
    );
  });

  test('文字色の固定プリセットは、アクセントの8色（不透明）＋白の9種類', () {
    expect(kDefaultColorPresets.length, 8);
    expect(kDefaultColorPresets, contains('A997C6CC'));
    expect(kFontColorPresets.length, 9);
    expect(kFontColorPresets.last, 'FFFFFF');
    expect(kFontColorPresets.every((h) => h.length == 6), isTrue);
    expect(kFontColorPresets.first, 'F08300');
  });
}
