import 'package:daidai/features/chat/create_group_dialog.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/friend.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/friend_repository.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGroups implements GroupRepository {
  final List<int> createdWithMembers = [];

  @override
  Future<Group> createGroup({
    required String name,
    required AppUser owner,
    required List<AppUser> members,
    required bool roomsEnabled,
  }) async {
    createdWithMembers.add(members.length);
    // 後続の画面遷移は対象外。ここで止める。
    throw StateError('stop');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFriends implements FriendRepository {
  @override
  Stream<List<Friend>> watchFriends(String userId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('友達を1人も選ばなくても、自分だけの広場を作成できる', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final groups = _FakeGroups();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          groupRepositoryProvider.overrideWithValue(groups),
          friendRepositoryProvider.overrideWithValue(_FakeFriends()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CreateGroupDialogContent(
                currentUser: const AppUser(userId: 'u1', rhingSeed: 'seed'),
                onClose: () {},
                onCompleted: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '私の広場');
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('作成'));
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();
    expect(groups.createdWithMembers, [0]);
  });
}
