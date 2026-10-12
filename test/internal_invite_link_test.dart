import 'package:daidai/models/app_user.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/widgets/link_preview_card.dart';
import 'package:daidai/widgets/user_profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this.user);
  final AppUser user;

  @override
  Future<AppUser?> findByRhingSeed(String rhingSeed) async =>
      rhingSeed == user.rhingSeed ? user : null;

  @override
  Stream<AppUser?> watchUser(String userId) => Stream.value(user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('DaiDaiの招待リンクだけを判定する', () {
    final user = parseInternalInviteLink('https://daidai.rhing.jp/invite/aaa');
    expect(user?.rhingSeed, 'aaa');
    expect(user?.groupId, isNull);
    final group = parseInternalInviteLink(
      'https://daidai.rhing.jp/join/g1/1700000000',
    );
    expect(group?.groupId, 'g1');
    expect(parseInternalInviteLink('https://example.com/invite/aaa'), isNull);
    expect(parseInternalInviteLink('https://daidai.rhing.jp/other'), isNull);
  });

  testWidgets('招待リンクは相手のカードをアプリ内の描画で出す', (tester) async {
    const user = AppUser(userId: 'u1', rhingSeed: 'aaa');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userRepositoryProvider.overrideWithValue(_FakeUserRepository(user)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(
              url: 'https://daidai.rhing.jp/invite/aaa',
              isGekiga: false,
              isMe: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileCardView), findsOneWidget);
  });
}
