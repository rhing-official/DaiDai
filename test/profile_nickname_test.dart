import 'package:daidai/features/profile/profile_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/terminology_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/terminology_style_provider.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/foundation.dart';
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
  Future<List<AppUser>> getUsersByIds(List<String> userIds) async =>
      saved != null && userIds.contains(saved!.userId) ? [saved!] : [];

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
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    final list = List<Map<String, dynamic>>.from(
      (json[field] as List).cast<Map<String, dynamic>>(),
    )..add(value);
    json[field] = list;
    saved = AppUser.fromJson(json);
  }

  @override
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    final list = List<Map<String, dynamic>>.from(
      (json[field] as List).cast<Map<String, dynamic>>(),
    )..removeWhere((v) => mapEquals(v, value));
    json[field] = list;
    saved = AppUser.fromJson(json);
  }

  @override
  Future<void> setProfileField(String userId, String field, String? value) async {
    final base = saved ?? AppUser(userId: userId, rhingId: '');
    final json = base.toJson();
    json[field] = value;
    saved = AppUser.fromJson(json);
  }

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
        overrides: [
          userRepositoryProvider.overrideWithValue(fakeRepo),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialTerminologyStyleProvider.overrideWithValue(
            TerminologyStyle.worldview,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileTab(currentUser: user)),
        ),
      ),
    );

    await tester.tap(find.text('呼び名を追加'));
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
        overrides: [
          userRepositoryProvider.overrideWithValue(fakeRepo),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialTerminologyStyleProvider.overrideWithValue(
            TerminologyStyle.worldview,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfileTab(currentUser: user)),
        ),
      ),
    );

    await tester.tap(find.text('一言を追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'げんき');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('げんき'), findsWidgets);
  });
}
