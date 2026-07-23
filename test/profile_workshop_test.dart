import 'dart:typed_data';

import 'package:daidai/features/profile/profile_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> _pumpProfileTab(WidgetTester tester, AppUser user, _FakeUserRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
      child: MaterialApp(home: Scaffold(body: ProfileTab(currentUser: user))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('工房タブは常に3枠表示し、白紙枠をタップするとカードが作れる', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    // 3枠すべてが「+」の白紙カードとして表示される。
    expect(find.byIcon(Icons.add), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを作る'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '仕事用');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('仕事用'), findsOneWidget);
    expect(repo.saved?.profileCards.map((c) => c.name), contains('仕事用'));
    // 残り2枠は依然として白紙のまま。
    expect(find.byIcon(Icons.add), findsNWidgets(2));
  });

  testWidgets('既存カードをタップすると内容が入った選択画面が開く', (tester) async {
    const card = ProfileCard(id: 'c1', name: '既存カード');
    const user = AppUser(userId: 'u1', rhingId: 'taro', profileCards: [card]);
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('既存カード'));
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを編集'), findsOneWidget);
    expect(find.text('既存カード'), findsWidgets);
  });

  testWidgets('カード名が未入力のまま保存を押すとエラーが表示され、ダイアログは閉じない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('工房'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    // カード名を空のまま保存を押す。以前は_save()が無言でreturnするだけで、
    // ボタンを押しても何も起きていないように見えていた（ユーザー報告の再現）。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('プロフィールカードを作る'), findsOneWidget); // ダイアログはまだ開いたまま
    expect(find.text('入力してください'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('ニックネームが未入力のまま追加を押すとエラーが表示され、ダイアログは閉じない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('ニックネームを追加'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('ニックネームを追加'), findsWidgets); // ダイアログはまだ開いたまま
    expect(find.text('入力してください'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('ニックネームは指定字数（20字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('ニックネームを追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 30);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxNicknameLength);
  });

  testWidgets('ステメは指定字数（40字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('ステメを追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 60);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxStatusMessageLength);
  });
}
