import 'package:daidai/features/chat/join_request_banner.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_join_request.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  groupId: 'g1',
  name: 'g',
  ownerId: 'owner',
  memberIds: ['owner', 'mod', 'plain'],
  memberRoles: {'owner': 'owner'},
  memberPermissions: {
    'mod': ['manageJoinRequests'],
    'plain': ['createInvite'],
  },
);

class _FakeGroups implements GroupRepository {
  _FakeGroups(this.requests);

  final List<GroupJoinRequest> requests;
  final watched = <String>[];

  @override
  Stream<List<GroupJoinRequest>> watchJoinRequests(String groupId) {
    watched.add(groupId);
    return Stream.value(requests);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupJoinRequest _request(String id) => GroupJoinRequest(
  requestId: id,
  groupId: 'g1',
  requesterId: id,
  requesterRhingSeed: id,
  status: GroupJoinRequestStatus.pending,
);

void main() {
  Future<_FakeGroups> pump(
    WidgetTester tester, {
    required String userId,
    required int requestCount,
    AppUiStyle style = AppUiStyle.flat,
  }) async {
    final groups = _FakeGroups([
      for (var i = 0; i < requestCount; i++) _request('r$i'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupRepositoryProvider.overrideWithValue(groups),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(style),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: JoinRequestBanner(
              group: _group,
              currentUser: AppUser(userId: userId, rhingSeed: userId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return groups;
  }

  testWidgets('長には件数が出る', (tester) async {
    await pump(tester, userId: 'owner', requestCount: 2);
    expect(find.text('参加リクエストが2件あります'), findsOneWidget);
  });

  testWidgets('manageJoinRequests権限者にも出る', (tester) async {
    await pump(tester, userId: 'mod', requestCount: 1);
    expect(find.text('参加リクエストが1件あります'), findsOneWidget);
  });

  testWidgets('権限の無いメンバーには出ず、購読もしない', (tester) async {
    final groups = await pump(tester, userId: 'plain', requestCount: 3);
    expect(find.textContaining('参加リクエスト'), findsNothing);
    expect(groups.watched, isEmpty);
  });

  testWidgets('0件なら出ない', (tester) async {
    await pump(tester, userId: 'owner', requestCount: 0);
    expect(find.textContaining('参加リクエスト'), findsNothing);
  });

  for (final style in AppUiStyle.values) {
    testWidgets('${style.name}でも表示できる', (tester) async {
      await pump(tester, userId: 'owner', requestCount: 1, style: style);
      expect(find.text('参加リクエストが1件あります'), findsOneWidget);
    });
  }
}
