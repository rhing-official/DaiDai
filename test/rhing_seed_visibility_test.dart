import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/widgets/user_profile_card_view.dart';

void main() {
  const card = ProfileCard(id: 'c', name: 'n');

  test('カードのRhing Seed表示は既定オフで、保存・復元できる', () {
    expect(card.showRhingSeed, isFalse);
    expect(card.toJson().containsKey('showRhingSeed'), isFalse);
    final on = card.copyWith(showRhingSeed: true);
    expect(ProfileCard.fromJson(on.toJson()).showRhingSeed, isTrue);
  });

  test('カードで載せる設定の時だけ、閲覧側でRhing Seedを出す', () {
    const user = AppUser(
      userId: 'u',
      rhingSeed: 'seed',
      profileCards: [card],
      activeProfileCardId: 'c',
    );
    expect(user.effectiveShowRhingSeedFor(null), isFalse);
    final shown = user.copyWith(
      profileCards: [card.copyWith(showRhingSeed: true)],
    );
    expect(shown.effectiveShowRhingSeedFor(null), isTrue);
  });

  test('Seed検索は未設定なら出る、falseの時だけ出ない', () {
    const base = AppUser(userId: 'u', rhingSeed: 's');
    expect(base.isSeedSearchable, isTrue);
    expect(
      AppUser.fromJson({
        ...base.toJson(),
        'seedSearchable': false,
      }).isSeedSearchable,
      isFalse,
    );
    expect(
      AppUser.fromJson({
        ...base.toJson(),
        'seedSearchable': true,
      }).isSeedSearchable,
      isTrue,
    );
    expect(base.copyWith().isSeedSearchable, isTrue);
  });

  Widget host(AppUser user, {bool copy = false}) => MaterialApp(
    home: Scaffold(
      body: UserProfileCardView(
        user: user,
        width: 300,
        height: 375,
        copyRhingSeed: copy,
      ),
    ),
  );

  testWidgets('設定オンで呼び名の下に@seedが出て、タップでコピー表示になる', (tester) async {
    final user = AppUser(
      userId: 'u',
      rhingSeed: 'seed',
      nicknames: const [Nickname(id: 'n', text: 'ミケ')],
      activeNicknameId: 'n',
      profileCards: [card.copyWith(showRhingSeed: true, nicknameId: 'n')],
      activeProfileCardId: 'c',
    );
    await tester.pumpWidget(host(user, copy: true));
    expect(find.text('@seed'), findsOneWidget);
    await tester.tap(find.text('@seed'));
    await tester.pump();
    expect(find.text('@seed'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('@seed'), findsOneWidget);
  });

  testWidgets('設定オフ、または呼び名が無い時は重ねて出さない', (tester) async {
    const off = AppUser(
      userId: 'u',
      rhingSeed: 'seed',
      nicknames: [Nickname(id: 'n', text: 'ミケ')],
      activeNicknameId: 'n',
    );
    await tester.pumpWidget(host(off));
    expect(find.text('@seed'), findsNothing);

    final noName = AppUser(
      userId: 'u',
      rhingSeed: 'seed',
      profileCards: [card.copyWith(showRhingSeed: true)],
      activeProfileCardId: 'c',
    );
    await tester.pumpWidget(host(noName));
    expect(find.text('@seed'), findsOneWidget); // 見出しの@seedだけ
  });
}
