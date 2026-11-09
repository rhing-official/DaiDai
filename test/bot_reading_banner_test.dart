import 'package:daidai/features/chat/bot_reading_banner.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/bot.dart';
import 'package:daidai/models/direct_message.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_role.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/bot_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  groupId: 'g1',
  name: 'g',
  ownerId: 'owner',
  memberIds: ['owner', 'plain'],
  memberRoles: {'owner': 'owner'},
);

class _FakeBots implements BotRepository {
  _FakeBots(this.bots);

  final List<GroupBot> bots;

  @override
  Stream<List<GroupBot>> watchConversationBots(BotConversation conversation) =>
      Stream.value(bots);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupBot _bot(String name, GroupBotStatus status) =>
    GroupBot(botId: name, name: name, ownerUserId: 'owner', status: status);

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<GroupBot> bots, {
    bool dm = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          botRepositoryProvider.overrideWithValue(_FakeBots(bots)),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BotReadingBanner(
              group: dm ? null : _group,
              dm: dm
                  ? const DirectMessage(
                      dmId: 'd1',
                      participants: ['owner', 'plain'],
                      participantRhingSeeds: {},
                    )
                  : null,
              currentUser: const AppUser(userId: 'plain', rhingSeed: 'plain'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有効なBOTがあれば、権限の無いメンバーにも名前が出る', (tester) async {
    await pump(tester, [
      _bot('Claude', GroupBotStatus.active),
      _bot('承認待ち', GroupBotStatus.pending),
    ]);
    expect(find.text('BOT（Claude）がこの広場のメッセージを読めます'), findsOneWidget);
  });

  testWidgets('一対では「この一対」と出る', (tester) async {
    await pump(tester, [_bot('Claude', GroupBotStatus.active)], dm: true);
    expect(find.text('BOT（Claude）がこの一対のメッセージを読めます'), findsOneWidget);
  });

  testWidgets('承認待ちだけなら何も出ない', (tester) async {
    await pump(tester, [_bot('承認待ち', GroupBotStatus.pending)]);
    expect(find.byType(InkWell), findsNothing);
  });

  test('addBotsは権限の一覧に含まれる', () {
    expect(GroupPermission.all, contains(GroupPermission.addBots));
  });
}
