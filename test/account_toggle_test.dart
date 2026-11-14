import 'package:daidai/l10n/strings.dart';
import 'package:daidai/features/settings/account_toggle.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/saved_account.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/account_switcher_providers.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/repositories/auth_repository.dart';
import 'package:daidai/repositories/saved_accounts_store.dart';
import 'package:daidai/repositories/switch_session_repository.dart';
import 'package:daidai/services/account_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sessions implements SwitchSessionRepository {
  @override
  Future<void> revoke(SavedAccount account) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AccountSwitcher _switcher(_Store store) => AccountSwitcher(
  sessions: _Sessions(),
  store: store,
  auth: _Auth(),
  resetLocalState: (_) async => true,
  reloadPage: () {},
);

class _Store implements SavedAccountsStore {
  _Store(this.accounts);
  final List<SavedAccount> accounts;
  @override
  Future<List<SavedAccount>> load() async => List.of(accounts);
  @override
  Future<void> save(SavedAccount a) async => accounts.add(a);
  @override
  Future<void> remove(String uid) async =>
      accounts.removeWhere((a) => a.uid == uid);
  @override
  Future<PendingAccountAdd?> loadPending() async => null;
  @override
  Future<void> savePending(PendingAccountAdd p) async {}
  @override
  Future<void> clearPending() async {}
}

SavedAccount _saved(String uid) =>
    SavedAccount(uid: uid, sessionId: 's', secret: 'x', rhingSeed: uid);

Future<void> _pump(
  WidgetTester tester,
  List<SavedAccount> saved, {
  AppUiStyle style = AppUiStyle.flat,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountSwitcherProvider.overrideWithValue(_switcher(_Store(saved))),
        initialAppUiStyleProvider.overrideWithValue(style),
        initialAccentColorProvider.overrideWithValue(kDefaultAccentColor),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AccountToggle(
            strings: Strings.ja,
            currentUser: const AppUser(userId: 'A', rhingSeed: 'alice'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('今のアカウントだけなら、今のアカウントと「追加」の2区画（管理は出ない）', (tester) async {
    await _pump(tester, [_saved('A')]);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text(Strings.ja.switchAccountsAdd), findsOneWidget);
    expect(find.text(Strings.ja.switchAccountsLongPressHint), findsNothing);
  });

  testWidgets('2つ保存すると、2アカウント＋「追加」。seedはアイコンの下に出て、管理が出る', (tester) async {
    await _pump(tester, [_saved('A'), _saved('B')]);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('@B'), findsOneWidget);
    expect(find.text(Strings.ja.switchAccountsAdd), findsOneWidget);
    expect(find.text(Strings.ja.switchAccountsLongPressHint), findsOneWidget);
  });

  testWidgets('3つ保存すると上限なので「追加」の区画は出ない', (tester) async {
    await _pump(tester, [_saved('A'), _saved('B'), _saved('C')]);
    expect(find.text('@B'), findsOneWidget);
    expect(find.text('@C'), findsOneWidget);
    expect(find.text(Strings.ja.switchAccountsAdd), findsNothing);
  });

  testWidgets('長押しで取り外すと、その区画が消える', (tester) async {
    final store = _Store([_saved('A'), _saved('B')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSwitcherProvider.overrideWithValue(_switcher(store)),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AccountToggle(
              strings: Strings.ja,
              currentUser: const AppUser(userId: 'A', rhingSeed: 'alice'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 管理のポップアップは無い。他のアカウントの区画を長押しすると取り外しの確認が出る。
    await tester.longPress(find.text('@B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Strings.ja.switchAccountsRemove));
    await tester.pumpAndSettle();
    expect(store.accounts.map((a) => a.uid), ['A']);
  });

  for (final style in [AppUiStyle.gekiga, AppUiStyle.glass, AppUiStyle.block]) {
    testWidgets('${style.name}でも、区画が崩れず並び、押して切り替えられる', (tester) async {
      await _pump(tester, [_saved('A'), _saved('B')], style: style);
      expect(tester.takeException(), isNull);
      expect(find.text('@alice'), findsOneWidget);
      expect(find.text('@B'), findsOneWidget);
      // 3区画（今のアカウント・もう1つ・追加）が、横に並んでいる。
      final alice = tester.getRect(find.text('@alice'));
      final other = tester.getRect(find.text('@B'));
      expect(alice.center.dy, closeTo(other.center.dy, 1));
      expect(alice.center.dx, lessThan(other.center.dx));
    });
  }
}
