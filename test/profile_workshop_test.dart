import 'dart:async';

import 'package:daidai/features/profile/profile_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/terminology_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/terminology_style_provider.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUserRepository implements UserRepository {
  AppUser? saved;

  // 特定のフィールドへの書き込みだけを意図的に遅延させ、複数の追加操作が
  // 重なった状況（例: 遅いアイコンアップロード中に速いニックネーム追加が
  // 先に完了する）を再現するためのフック。
  String? delayedField;
  Completer<void>? _delayGate;

  void blockField(String field) {
    delayedField = field;
    _delayGate = Completer<void>();
  }

  void releaseField() => _delayGate?.complete();

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
    if (field == delayedField) await _delayGate!.future;
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

Future<void> _pumpProfileTab(WidgetTester tester, AppUser user, _FakeUserRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
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

    await tester.tap(find.text('呼び名を追加'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();

    expect(find.text('呼び名を追加'), findsWidgets); // ダイアログはまだ開いたまま
    expect(find.text('入力してください'), findsOneWidget);
    expect(repo.saved, isNull);
  });

  testWidgets('ニックネームは指定字数（20字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('呼び名を追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 30);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxNicknameLength);
  });

  testWidgets('ステメは指定字数（40字）を超えて入力できない', (tester) async {
    const user = AppUser(userId: 'u1', rhingId: 'taro');
    final repo = _FakeUserRepository();
    await _pumpProfileTab(tester, user, repo);

    await tester.tap(find.text('一言を追加'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'あ' * 60);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxStatusMessageLength);
  });

  testWidgets(
    '遅いステメ保存の完了中に追加したニックネームが消えない（lost update回帰テスト）',
    (tester) async {
      // 実際のバグ再現: アイコンアップロード（Storage往復で数秒かかる）の
      // ような遅い保存処理が完了する前に、別の項目（ニックネーム）を
      // 追加すると、以前の実装（AppUser全体をset()で丸ごと上書き）では
      // 後から完了した書き込みが先の書き込みを消してしまっていた。
      // ここではステメの保存をわざと遅延させ、その間にニックネームを
      // 追加した場合に両方とも生き残ることを検証する。
      const user = AppUser(userId: 'u1', rhingId: 'taro');
      final repo = _FakeUserRepository();
      await _pumpProfileTab(tester, user, repo);

      repo.blockField('statusMessages');

      // ステメの保存を開始する（サーバー側書き込みは_delayGateでブロックされ、
      // まだ完了しない）。
      await tester.tap(find.text('一言を追加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'げんき');
      await tester.tap(find.text('追加'));
      await tester.pump();

      // ステメの保存がまだ完了していない間に、ニックネームを追加する。
      await tester.tap(find.text('呼び名を追加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'たろ');
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();

      // ニックネームは（ステメの保存を待たずに）先に反映されているはず。
      expect(repo.saved?.nicknames.map((n) => n.text), contains('たろ'));

      // 遅延させていたステメの保存を完了させる。
      repo.releaseField();
      await tester.pumpAndSettle();

      // ステメが反映された後も、先に追加したニックネームが消えていないこと
      // （lost updateが起きていないこと）を確認する。
      expect(repo.saved?.statusMessages.map((m) => m.text), contains('げんき'));
      expect(repo.saved?.nicknames.map((n) => n.text), contains('たろ'));
    },
  );
}
