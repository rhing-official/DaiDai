import 'dart:typed_data';

import 'package:daidai/features/profile/profile_tab.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore/Storageを使わない、身だしなみタブのUIロジックだけを検証するための
/// インメモリのフェイクリポジトリ。
class _FakeUserRepository implements UserRepository {
  AppUser? saved;

  @override
  Future<AppUser?> getUser(String userId) async => saved;

  @override
  Stream<AppUser?> watchUser(String userId) => Stream.value(saved);

  @override
  Future<void> createUser(AppUser user) async => saved = user;

  @override
  Future<AppUser?> findByRhingId(String rhingId) async => null;

  @override
  Future<bool> isRhingIdAvailable(String rhingId) async => true;

  @override
  Future<void> updateUser(AppUser user) async => saved = user;

  @override
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes) {
    throw UnimplementedError();
  }

  @override
  Future<ProfileMaterial> uploadBackgroundImage(String userId, Uint8List bytes) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteProfileMaterial(ProfileMaterial material) async {}
}

void main() {
  testWidgets('ニックネームを追加すると一覧に表示される', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final fakeRepo = _FakeUserRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(
          home: Scaffold(body: ProfileTab(currentUser: user)),
        ),
      ),
    );

    await tester.tap(find.text('ニックネームを追加'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'たろ');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('たろ'), findsWidgets);
    expect(fakeRepo.saved?.nicknames.map((n) => n.text), contains('たろ'));
  });

  testWidgets('ステメを追加すると一覧に表示される', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final fakeRepo = _FakeUserRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(
          home: Scaffold(body: ProfileTab(currentUser: user)),
        ),
      ),
    );

    await tester.tap(find.text('ステメを追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'げんき');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('げんき'), findsWidgets);
  });
}
